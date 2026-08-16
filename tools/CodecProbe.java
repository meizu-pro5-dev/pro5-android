import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.Image;
import android.media.ImageReader;
import android.graphics.ImageFormat;
import android.view.Surface;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class CodecProbe {
    private static final long TIMEOUT_US = 50_000;
    private static final long DEADLINE_MS = 20_000;

    private CodecProbe() {}

    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            usage();
            return;
        }
        try {
            if ("list".equals(args[0])) {
                listCodecs();
            } else if ("create".equals(args[0]) && args.length >= 2) {
                createCodec(args[1]);
            } else if ("decode".equals(args[0]) && args.length >= 2) {
                String kind = args.length >= 3 ? args[2] : "any";
                decode(args[1], kind);
            } else if ("surface-decode".equals(args[0]) && args.length >= 2) {
                String mode = args.length >= 3 ? args[2] : "private";
                String codecName = args.length >= 4 ? args[3] : null;
                surfaceDecode(args[1], mode, codecName);
            } else if ("encode".equals(args[0]) && args.length >= 5) {
                int width = Integer.parseInt(args[3]);
                int height = Integer.parseInt(args[4]);
                int frames = args.length >= 6 ? Integer.parseInt(args[5]) : 60;
                encodeRaw(args[1], args[2], width, height, frames);
            } else if ("concurrent".equals(args[0]) && args.length >= 3) {
                concurrentDecode(args[1], Integer.parseInt(args[2]));
            } else if ("concurrent-full".equals(args[0]) && args.length >= 3) {
                concurrentFullDecode(args[1], Integer.parseInt(args[2]));
            } else {
                usage();
            }
        } catch (Throwable t) {
            System.out.println("RESULT=FAIL exception=" + t);
            t.printStackTrace(System.out);
        }
    }

    private static void usage() {
        System.out.println("usage: CodecProbe list");
        System.out.println("   or: CodecProbe create <codec-name>");
        System.out.println("   or: CodecProbe decode <path> [video|audio|any]");
        System.out.println("   or: CodecProbe surface-decode <video-path> [private|yuv] [codec]");
        System.out.println("   or: CodecProbe encode <codec-name> <mime> <width> <height> [frames]");
        System.out.println("   or: CodecProbe concurrent <video-path> <instances>");
        System.out.println("   or: CodecProbe concurrent-full <video-path> <instances>");
    }

    private static MediaCodecInfo[] codecInfos() {
        return new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos();
    }

    private static String[] matchingTypes(MediaCodecInfo info, String prefix) {
        List<String> result = new ArrayList<>();
        for (String type : info.getSupportedTypes()) {
            if (prefix == null || type.startsWith(prefix)) {
                result.add(type);
            }
        }
        return result.toArray(new String[result.size()]);
    }

    private static void listCodecs() {
        System.out.println("RESULT=LIST");
        for (MediaCodecInfo info : codecInfos()) {
            String[] types = info.getSupportedTypes();
            if (types.length == 0) {
                continue;
            }
            System.out.println("codec=" + info.getName() + " encoder=" + info.isEncoder()
                    + " types=" + Arrays.toString(types));
            for (String type : types) {
                try {
                    MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
                    System.out.println("  type=" + type + " colors="
                            + Arrays.toString(caps.colorFormats));
                    MediaCodecInfo.VideoCapabilities v = caps.getVideoCapabilities();
                    if (v != null) {
                        System.out.println("  video=" + v.getSupportedWidths() + "x"
                                + v.getSupportedHeights() + " rates=" + v.getSupportedFrameRates());
                    }
                } catch (Throwable t) {
                    System.out.println("  type=" + type + " caps_error=" + t);
                }
            }
        }
    }

    private static void createCodec(String codecName) throws Exception {
        MediaCodec codec = null;
        try {
            System.out.println("TEST=create codec=" + codecName);
            codec = MediaCodec.createByCodecName(codecName);
            System.out.println("RESULT=PASS created=" + codec.getName());
        } finally {
            if (codec != null) {
                try { codec.release(); } catch (Throwable ignored) {}
            }
        }
    }

    private static MediaCodecInfo findDecoder(String mime) {
        MediaCodecInfo fallback = null;
        for (MediaCodecInfo info : codecInfos()) {
            if (info.isEncoder()) {
                continue;
            }
            for (String type : info.getSupportedTypes()) {
                if (mime.equalsIgnoreCase(type)) {
                    if (fallback == null) {
                        fallback = info;
                    }
                    if (info.getName().startsWith("OMX.Exynos.")) {
                        return info;
                    }
                }
            }
        }
        return fallback;
    }

    private static void decode(String path, String kind) throws Exception {
        long startedAtMs = System.currentTimeMillis();
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(path);
            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String mime = candidate.getString(MediaFormat.KEY_MIME);
                if (("video".equals(kind) && !mime.startsWith("video/"))
                        || ("audio".equals(kind) && !mime.startsWith("audio/"))) {
                    continue;
                }
                track = i;
                format = candidate;
                break;
            }
            if (track < 0 || format == null) {
                throw new IllegalStateException("no matching track kind=" + kind);
            }
            String mime = format.getString(MediaFormat.KEY_MIME);
            MediaCodecInfo info = findDecoder(mime);
            if (info == null) {
                throw new IllegalStateException("no decoder for " + mime);
            }
            System.out.println("TEST=decode path=" + path + " kind=" + kind
                    + " mime=" + mime + " format=" + format);
            System.out.println("decoder=" + info.getName() + " encoder=" + info.isEncoder());
            extractor.selectTrack(track);
            codec = MediaCodec.createByCodecName(info.getName());
            codec.configure(format, null, null, 0);
            codec.start();
            ByteBuffer[] inputBuffers = codec.getInputBuffers();
            MediaCodec.BufferInfo outputInfo = new MediaCodec.BufferInfo();
            boolean inputEos = false;
            boolean outputEos = false;
            long inputBytes = 0;
            long outputBytes = 0;
            int inputSamples = 0;
            int outputBuffers = 0;
            long deadline = System.currentTimeMillis() + DEADLINE_MS;
            while (!outputEos && System.currentTimeMillis() < deadline) {
                if (!inputEos) {
                    int inputIndex = codec.dequeueInputBuffer(TIMEOUT_US);
                    if (inputIndex >= 0) {
                        ByteBuffer input = inputBuffers[inputIndex];
                        input.clear();
                        int sampleSize = extractor.readSampleData(input, 0);
                        long pts = extractor.getSampleTime();
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, sampleSize, pts, 0);
                            inputBytes += sampleSize;
                            inputSamples++;
                            extractor.advance();
                        }
                    }
                }
                int outputIndex = codec.dequeueOutputBuffer(outputInfo, TIMEOUT_US);
                if (outputIndex >= 0) {
                    outputBuffers++;
                    outputBytes += outputInfo.size;
                    if ((outputInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputEos = true;
                    }
                    codec.releaseOutputBuffer(outputIndex, false);
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("output_format=" + codec.getOutputFormat());
                }
            }
            if (!outputEos) {
                throw new IllegalStateException("decode timeout inputSamples=" + inputSamples
                        + " outputBuffers=" + outputBuffers);
            }
            System.out.println("RESULT=PASS decoder=" + info.getName() + " mime=" + mime
                    + " inputSamples=" + inputSamples + " inputBytes=" + inputBytes
                    + " outputBuffers=" + outputBuffers + " outputBytes=" + outputBytes
                    + " elapsedMs=" + (System.currentTimeMillis() - startedAtMs));
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Throwable ignored) {}
                try { codec.release(); } catch (Throwable ignored) {}
            }
            extractor.release();
        }
    }

    private static void surfaceDecode(String path, String mode, String requestedCodec)
            throws Exception {
        long startedAtMs = System.currentTimeMillis();
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        ImageReader reader = null;
        Surface surface = null;
        try {
            extractor.setDataSource(path);
            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String candidateMime = candidate.getString(MediaFormat.KEY_MIME);
                if (candidateMime != null && candidateMime.startsWith("video/")) {
                    track = i;
                    format = candidate;
                    break;
                }
            }
            if (track < 0 || format == null) {
                throw new IllegalStateException("no video track");
            }
            String mime = format.getString(MediaFormat.KEY_MIME);
            MediaCodecInfo info = requestedCodec == null ? findDecoder(mime) : null;
            String codecName = requestedCodec == null
                    ? (info == null ? null : info.getName()) : requestedCodec;
            if (codecName == null) {
                throw new IllegalStateException("no decoder for " + mime);
            }
            int width = format.getInteger(MediaFormat.KEY_WIDTH);
            int height = format.getInteger(MediaFormat.KEY_HEIGHT);
            int readerFormat;
            if ("private".equals(mode)) {
                readerFormat = ImageFormat.PRIVATE;
            } else if ("yuv".equals(mode)) {
                readerFormat = ImageFormat.YUV_420_888;
            } else {
                throw new IllegalArgumentException("unknown surface mode=" + mode);
            }
            reader = ImageReader.newInstance(width, height, readerFormat, 8);
            surface = reader.getSurface();
            System.out.println("TEST=surface-decode path=" + path + " mime=" + mime
                    + " decoder=" + codecName + " size=" + width + "x" + height
                    + " mode=" + mode + " readerFormat=" + readerFormat);
            extractor.selectTrack(track);
            codec = MediaCodec.createByCodecName(codecName);
            codec.configure(format, surface, null, 0);
            codec.start();
            ByteBuffer[] inputBuffers = codec.getInputBuffers();
            MediaCodec.BufferInfo outputInfo = new MediaCodec.BufferInfo();
            boolean inputEos = false;
            boolean outputEos = false;
            int inputSamples = 0;
            int outputBuffers = 0;
            int renderedBuffers = 0;
            int acquiredImages = 0;
            long deadline = System.currentTimeMillis() + DEADLINE_MS;
            while (!outputEos && System.currentTimeMillis() < deadline) {
                acquiredImages += drainImages(reader);
                if (!inputEos) {
                    int inputIndex = codec.dequeueInputBuffer(TIMEOUT_US);
                    if (inputIndex >= 0) {
                        ByteBuffer input = inputBuffers[inputIndex];
                        input.clear();
                        int sampleSize = extractor.readSampleData(input, 0);
                        long pts = extractor.getSampleTime();
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, sampleSize, pts, 0);
                            inputSamples++;
                            extractor.advance();
                        }
                    }
                }
                int outputIndex = codec.dequeueOutputBuffer(outputInfo, TIMEOUT_US);
                if (outputIndex >= 0) {
                    outputBuffers++;
                    outputEos = (outputInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    boolean render = outputInfo.size > 0 && !outputEos;
                    codec.releaseOutputBuffer(outputIndex, render);
                    if (render) {
                        renderedBuffers++;
                    }
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("output_format=" + codec.getOutputFormat());
                }
            }
            long imageDeadline = System.currentTimeMillis() + 1_000;
            while (System.currentTimeMillis() < imageDeadline && acquiredImages < 1) {
                acquiredImages += drainImages(reader);
                if (acquiredImages < 1) {
                    Thread.sleep(5);
                }
            }
            if (!outputEos || renderedBuffers == 0 || acquiredImages == 0) {
                throw new IllegalStateException("surface decode incomplete eos=" + outputEos
                        + " inputSamples=" + inputSamples + " outputBuffers=" + outputBuffers
                        + " renderedBuffers=" + renderedBuffers
                        + " acquiredImages=" + acquiredImages);
            }
            System.out.println("RESULT=PASS surface decoder=" + codecName + " mime=" + mime
                    + " mode=" + mode
                    + " inputSamples=" + inputSamples + " outputBuffers=" + outputBuffers
                    + " renderedBuffers=" + renderedBuffers
                    + " acquiredImages=" + acquiredImages
                    + " elapsedMs=" + (System.currentTimeMillis() - startedAtMs));
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Throwable ignored) {}
                try { codec.release(); } catch (Throwable ignored) {}
            }
            if (surface != null) {
                surface.release();
            }
            if (reader != null) {
                reader.close();
            }
            extractor.release();
        }
    }

    private static int drainImages(ImageReader reader) {
        int count = 0;
        for (;;) {
            Image image = null;
            try {
                image = reader.acquireNextImage();
                if (image == null) {
                    return count;
                }
                count++;
            } finally {
                if (image != null) {
                    image.close();
                }
            }
        }
    }

    private static void encodeRaw(String codecName, String mime, int width, int height,
            int requestedFrames)
            throws Exception {
        if (requestedFrames < 1 || requestedFrames > 600) {
            throw new IllegalArgumentException("frames must be in range 1..600");
        }
        long startedAtMs = System.currentTimeMillis();
        MediaCodec codec = null;
        try {
            System.out.println("TEST=encode codec=" + codecName + " mime=" + mime
                    + " size=" + width + "x" + height + " frames=" + requestedFrames);
            codec = MediaCodec.createByCodecName(codecName);
            MediaFormat format = MediaFormat.createVideoFormat(mime, width, height);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar);
            format.setInteger(MediaFormat.KEY_BIT_RATE, 2_000_000);
            format.setInteger(MediaFormat.KEY_FRAME_RATE, 30);
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            codec.start();
            ByteBuffer[] inputBuffers = codec.getInputBuffers();
            MediaCodec.BufferInfo outputInfo = new MediaCodec.BufferInfo();
            int outputBuffers = 0;
            long outputBytes = 0;
            int inputFrames = 0;
            boolean inputEos = false;
            boolean outputEos = false;
            long deadline = System.currentTimeMillis() + DEADLINE_MS;
            while (inputFrames < requestedFrames && System.currentTimeMillis() < deadline) {
                int inputIndex = codec.dequeueInputBuffer(TIMEOUT_US);
                if (inputIndex >= 0) {
                    ByteBuffer input = inputBuffers[inputIndex];
                    input.clear();
                    int frameSize = width * height * 3 / 2;
                    if (input.capacity() < frameSize) {
                        throw new IllegalStateException("input capacity=" + input.capacity()
                                + " smaller than frame=" + frameSize);
                    }
                    int y = input.position();
                    for (int row = 0; row < height; row++) {
                        for (int col = 0; col < width; col++) {
                            input.put((byte) ((row + col + inputFrames * 3) & 0xff));
                        }
                    }
                    for (int i = 0; i < width * height / 4; i++) {
                        input.put((byte) (96 + (inputFrames & 0x1f)));
                    }
                    for (int i = 0; i < width * height / 4; i++) {
                        input.put((byte) (160 - (inputFrames & 0x1f)));
                    }
                    codec.queueInputBuffer(inputIndex, y, frameSize,
                            inputFrames * 1_000_000L / 30, 0);
                    inputFrames++;
                }
                outputBuffers += drainEncoder(codec, outputInfo);
                outputBytes += lastDrainedBytes;
            }
            while (!inputEos && System.currentTimeMillis() < deadline) {
                int index = codec.dequeueInputBuffer(TIMEOUT_US);
                if (index >= 0) {
                    codec.queueInputBuffer(index, 0, 0, inputFrames * 1_000_000L / 30,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                    inputEos = true;
                }
                outputBuffers += drainEncoder(codec, outputInfo);
                outputBytes += lastDrainedBytes;
            }
            while (!outputEos && System.currentTimeMillis() < deadline) {
                int index = codec.dequeueOutputBuffer(outputInfo, TIMEOUT_US);
                if (index >= 0) {
                    outputBuffers++;
                    outputBytes += outputInfo.size;
                    outputEos = (outputInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    codec.releaseOutputBuffer(index, false);
                } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("output_format=" + codec.getOutputFormat());
                }
            }
            if (!outputEos || outputBuffers == 0 || outputBytes == 0) {
                throw new IllegalStateException("encode incomplete eos=" + outputEos
                        + " inputFrames=" + inputFrames + " outputBuffers=" + outputBuffers
                        + " outputBytes=" + outputBytes);
            }
            System.out.println("RESULT=PASS encoder=" + codecName + " mime=" + mime
                    + " size=" + width + "x" + height + " inputFrames=" + inputFrames
                    + " outputBuffers=" + outputBuffers + " outputBytes=" + outputBytes
                    + " elapsedMs=" + (System.currentTimeMillis() - startedAtMs));
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Throwable ignored) {}
                try { codec.release(); } catch (Throwable ignored) {}
            }
        }
    }

    private static long lastDrainedBytes;

    private static int drainEncoder(MediaCodec codec, MediaCodec.BufferInfo info) {
        int count = 0;
        lastDrainedBytes = 0;
        for (;;) {
            int index = codec.dequeueOutputBuffer(info, 0);
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                System.out.println("output_format=" + codec.getOutputFormat());
                continue;
            }
            if (index < 0) {
                break;
            }
            count++;
            lastDrainedBytes += info.size;
            codec.releaseOutputBuffer(index, false);
        }
        return count;
    }

    private static void concurrentDecode(String path, int requested) throws Exception {
        if (requested < 1 || requested > 32) {
            throw new IllegalArgumentException("instances must be in range 1..32");
        }
        long startedAtMs = System.currentTimeMillis();
        MediaExtractor extractor = new MediaExtractor();
        List<MediaCodec> codecs = new ArrayList<>();
        try {
            extractor.setDataSource(path);
            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String candidateMime = candidate.getString(MediaFormat.KEY_MIME);
                if (candidateMime != null && candidateMime.startsWith("video/")) {
                    track = i;
                    format = candidate;
                    break;
                }
            }
            if (track < 0 || format == null) {
                throw new IllegalStateException("no video track");
            }
            String mime = format.getString(MediaFormat.KEY_MIME);
            MediaCodecInfo info = findDecoder(mime);
            if (info == null) {
                throw new IllegalStateException("no decoder for " + mime);
            }
            extractor.selectTrack(track);
            int maxInput = format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)
                    ? format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) : 4 * 1024 * 1024;
            ByteBuffer sampleBuffer = ByteBuffer.allocate(Math.max(maxInput, 4 * 1024 * 1024));
            int sampleSize = extractor.readSampleData(sampleBuffer, 0);
            if (sampleSize <= 0) {
                throw new IllegalStateException("unable to read first compressed sample");
            }
            byte[] sample = new byte[sampleSize];
            sampleBuffer.position(0);
            sampleBuffer.get(sample, 0, sampleSize);
            long sampleTimeUs = Math.max(0, extractor.getSampleTime());
            int sampleFlags = extractor.getSampleFlags();

            System.out.println("TEST=concurrent decoder=" + info.getName() + " mime=" + mime
                    + " requested=" + requested + " sampleBytes=" + sampleSize);
            for (int i = 0; i < requested; i++) {
                MediaCodec codec = MediaCodec.createByCodecName(info.getName());
                codec.configure(format, null, null, 0);
                codec.start();
                codecs.add(codec);

                ByteBuffer[] inputs = codec.getInputBuffers();
                int inputIndex = dequeueInput(codec, 2_000);
                ByteBuffer input = inputs[inputIndex];
                input.clear();
                if (input.capacity() < sampleSize) {
                    throw new IllegalStateException("instance=" + i + " input capacity="
                            + input.capacity() + " sample=" + sampleSize);
                }
                input.put(sample);
                codec.queueInputBuffer(inputIndex, 0, sampleSize, sampleTimeUs, sampleFlags);
                int eosIndex = dequeueInput(codec, 2_000);
                codec.queueInputBuffer(eosIndex, 0, 0, sampleTimeUs + 1,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                System.out.println("instance_started=" + (i + 1));
            }

            int[] outputCounts = new int[requested];
            boolean[] eos = new boolean[requested];
            int eosCount = 0;
            MediaCodec.BufferInfo outputInfo = new MediaCodec.BufferInfo();
            long deadline = System.currentTimeMillis() + DEADLINE_MS;
            while (eosCount < requested && System.currentTimeMillis() < deadline) {
                boolean madeProgress = false;
                for (int i = 0; i < requested; i++) {
                    if (eos[i]) {
                        continue;
                    }
                    int outputIndex = codecs.get(i).dequeueOutputBuffer(outputInfo, 0);
                    if (outputIndex >= 0) {
                        madeProgress = true;
                        outputCounts[i]++;
                        if ((outputInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            eos[i] = true;
                            eosCount++;
                        }
                        codecs.get(i).releaseOutputBuffer(outputIndex, false);
                    }
                }
                if (!madeProgress) {
                    Thread.sleep(5);
                }
            }
            int produced = 0;
            for (int count : outputCounts) {
                if (count > 0) {
                    produced++;
                }
            }
            if (eosCount != requested || produced != requested) {
                throw new IllegalStateException("concurrency incomplete active=" + codecs.size()
                        + " produced=" + produced + " eos=" + eosCount);
            }
            System.out.println("RESULT=PASS concurrent decoder=" + info.getName()
                    + " requested=" + requested + " active=" + codecs.size()
                    + " produced=" + produced + " eos=" + eosCount
                    + " elapsedMs=" + (System.currentTimeMillis() - startedAtMs));
        } finally {
            for (int i = codecs.size() - 1; i >= 0; i--) {
                try { codecs.get(i).stop(); } catch (Throwable ignored) {}
                try { codecs.get(i).release(); } catch (Throwable ignored) {}
            }
            extractor.release();
        }
    }

    private static int dequeueInput(MediaCodec codec, long timeoutMs) {
        long deadline = System.currentTimeMillis() + timeoutMs;
        int index;
        do {
            index = codec.dequeueInputBuffer(TIMEOUT_US);
        } while (index < 0 && System.currentTimeMillis() < deadline);
        if (index < 0) {
            throw new IllegalStateException("timed out waiting for input buffer");
        }
        return index;
    }

    private static void concurrentFullDecode(String path, int requested) throws Exception {
        if (requested < 1 || requested > 32) {
            throw new IllegalArgumentException("instances must be in range 1..32");
        }
        long startedAtMs = System.currentTimeMillis();
        MediaExtractor extractor = new MediaExtractor();
        List<MediaCodec> codecs = new ArrayList<>();
        try {
            extractor.setDataSource(path);
            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String candidateMime = candidate.getString(MediaFormat.KEY_MIME);
                if (candidateMime != null && candidateMime.startsWith("video/")) {
                    track = i;
                    format = candidate;
                    break;
                }
            }
            if (track < 0 || format == null) {
                throw new IllegalStateException("no video track");
            }
            String mime = format.getString(MediaFormat.KEY_MIME);
            MediaCodecInfo info = findDecoder(mime);
            if (info == null) {
                throw new IllegalStateException("no decoder for " + mime);
            }
            extractor.selectTrack(track);
            int maxInput = format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)
                    ? format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) : 4 * 1024 * 1024;
            ByteBuffer sampleBuffer = ByteBuffer.allocate(Math.max(maxInput, 4 * 1024 * 1024));
            List<byte[]> samples = new ArrayList<>();
            List<Long> sampleTimes = new ArrayList<>();
            List<Integer> sampleFlags = new ArrayList<>();
            for (;;) {
                sampleBuffer.clear();
                int size = extractor.readSampleData(sampleBuffer, 0);
                if (size < 0) {
                    break;
                }
                byte[] sample = new byte[size];
                sampleBuffer.position(0);
                sampleBuffer.get(sample, 0, size);
                samples.add(sample);
                sampleTimes.add(Math.max(0, extractor.getSampleTime()));
                sampleFlags.add(extractor.getSampleFlags());
                extractor.advance();
            }
            if (samples.isEmpty()) {
                throw new IllegalStateException("no compressed samples");
            }

            System.out.println("TEST=concurrent-full decoder=" + info.getName() + " mime=" + mime
                    + " requested=" + requested + " samplesPerInstance=" + samples.size());
            ByteBuffer[][] inputBuffers = new ByteBuffer[requested][];
            for (int i = 0; i < requested; i++) {
                MediaCodec codec = MediaCodec.createByCodecName(info.getName());
                codec.configure(format, null, null, 0);
                codec.start();
                codecs.add(codec);
                inputBuffers[i] = codec.getInputBuffers();
                System.out.println("instance_started=" + (i + 1));
            }

            int[] nextSample = new int[requested];
            boolean[] inputEos = new boolean[requested];
            boolean[] outputEos = new boolean[requested];
            int[] outputCounts = new int[requested];
            int outputEosCount = 0;
            MediaCodec.BufferInfo outputInfo = new MediaCodec.BufferInfo();
            long deadline = System.currentTimeMillis() + 60_000;
            while (outputEosCount < requested && System.currentTimeMillis() < deadline) {
                boolean madeProgress = false;
                for (int i = 0; i < requested; i++) {
                    MediaCodec codec = codecs.get(i);
                    if (!inputEos[i]) {
                        int inputIndex = codec.dequeueInputBuffer(0);
                        if (inputIndex >= 0) {
                            madeProgress = true;
                            if (nextSample[i] < samples.size()) {
                                byte[] sample = samples.get(nextSample[i]);
                                ByteBuffer input = inputBuffers[i][inputIndex];
                                input.clear();
                                if (input.capacity() < sample.length) {
                                    throw new IllegalStateException("instance=" + i
                                            + " input capacity=" + input.capacity()
                                            + " sample=" + sample.length);
                                }
                                input.put(sample);
                                codec.queueInputBuffer(inputIndex, 0, sample.length,
                                        sampleTimes.get(nextSample[i]),
                                        sampleFlags.get(nextSample[i]));
                                nextSample[i]++;
                            } else {
                                long eosTime = sampleTimes.get(sampleTimes.size() - 1) + 1;
                                codec.queueInputBuffer(inputIndex, 0, 0, eosTime,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                                inputEos[i] = true;
                            }
                        }
                    }
                    if (!outputEos[i]) {
                        for (;;) {
                            int outputIndex = codec.dequeueOutputBuffer(outputInfo, 0);
                            if (outputIndex < 0) {
                                break;
                            }
                            madeProgress = true;
                            outputCounts[i]++;
                            if ((outputInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                outputEos[i] = true;
                                outputEosCount++;
                            }
                            codec.releaseOutputBuffer(outputIndex, false);
                        }
                    }
                }
                if (!madeProgress) {
                    Thread.sleep(2);
                }
            }
            int completedInputs = 0;
            int produced = 0;
            int minOutputs = Integer.MAX_VALUE;
            int maxOutputs = 0;
            for (int i = 0; i < requested; i++) {
                if (nextSample[i] == samples.size() && inputEos[i]) {
                    completedInputs++;
                }
                if (outputCounts[i] > 0) {
                    produced++;
                }
                minOutputs = Math.min(minOutputs, outputCounts[i]);
                maxOutputs = Math.max(maxOutputs, outputCounts[i]);
            }
            if (completedInputs != requested || outputEosCount != requested
                    || produced != requested) {
                throw new IllegalStateException("full concurrency incomplete inputComplete="
                        + completedInputs + " produced=" + produced + " eos=" + outputEosCount
                        + " minOutputs=" + minOutputs + " maxOutputs=" + maxOutputs);
            }
            System.out.println("RESULT=PASS concurrent-full decoder=" + info.getName()
                    + " requested=" + requested + " active=" + codecs.size()
                    + " samplesPerInstance=" + samples.size()
                    + " minOutputs=" + minOutputs + " maxOutputs=" + maxOutputs
                    + " eos=" + outputEosCount
                    + " elapsedMs=" + (System.currentTimeMillis() - startedAtMs));
        } finally {
            for (int i = codecs.size() - 1; i >= 0; i--) {
                try { codecs.get(i).stop(); } catch (Throwable ignored) {}
                try { codecs.get(i).release(); } catch (Throwable ignored) {}
            }
            extractor.release();
        }
    }
}
