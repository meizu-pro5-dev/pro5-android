import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

public final class CodecRoundTrip {
    private static final long TIMEOUT_US = 50_000;
    private static final long DEADLINE_MS = 30_000;

    private CodecRoundTrip() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 6) {
            System.out.println("usage: CodecRoundTrip <encoder> <mime> <width> <height> <frames> <fps>");
            return;
        }
        try {
            run(args[0], args[1], Integer.parseInt(args[2]), Integer.parseInt(args[3]),
                    Integer.parseInt(args[4]), Integer.parseInt(args[5]));
        } catch (Throwable t) {
            System.out.println("RESULT=FAIL exception=" + t);
            t.printStackTrace(System.out);
        }
    }

    private static void run(String encoderName, String mime, int width, int height,
            int requestedFrames, int fps) throws Exception {
        if (requestedFrames < 1 || requestedFrames > 300 || fps < 1 || fps > 120) {
            throw new IllegalArgumentException("invalid frame count or rate");
        }
        System.out.println("TEST=roundtrip encoder=" + encoderName + " mime=" + mime
                + " size=" + width + "x" + height + " frames=" + requestedFrames
                + " fps=" + fps);

        List<byte[]> packets = new ArrayList<>();
        List<Long> packetTimesUs = new ArrayList<>();
        MediaFormat encodedFormat = null;
        long encodedBytes = 0;
        long encodeStartedMs = System.currentTimeMillis();
        MediaCodec encoder = null;
        try {
            encoder = MediaCodec.createByCodecName(encoderName);
            MediaFormat inputFormat = MediaFormat.createVideoFormat(mime, width, height);
            inputFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar);
            inputFormat.setInteger(MediaFormat.KEY_BIT_RATE, 2_000_000);
            inputFormat.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
            inputFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
            encoder.configure(inputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            encoder.start();

            ByteBuffer[] inputs = encoder.getInputBuffers();
            ByteBuffer[] outputs = encoder.getOutputBuffers();
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            int inputFrames = 0;
            boolean inputEos = false;
            boolean outputEos = false;
            long deadline = System.currentTimeMillis() + DEADLINE_MS;
            while (!outputEos && System.currentTimeMillis() < deadline) {
                if (!inputEos) {
                    int inputIndex = encoder.dequeueInputBuffer(TIMEOUT_US);
                    if (inputIndex >= 0) {
                        if (inputFrames < requestedFrames) {
                            ByteBuffer input = inputs[inputIndex];
                            input.clear();
                            int frameSize = fillYuv420p(input, width, height, inputFrames);
                            encoder.queueInputBuffer(inputIndex, 0, frameSize,
                                    inputFrames * 1_000_000L / fps, 0);
                            inputFrames++;
                        } else {
                            encoder.queueInputBuffer(inputIndex, 0, 0,
                                    inputFrames * 1_000_000L / fps,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        }
                    }
                }

                int outputIndex = encoder.dequeueOutputBuffer(info, TIMEOUT_US);
                if (outputIndex >= 0) {
                    if (info.size > 0
                            && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        ByteBuffer output = outputs[outputIndex].duplicate();
                        output.position(info.offset);
                        output.limit(info.offset + info.size);
                        byte[] packet = new byte[info.size];
                        output.get(packet);
                        packets.add(packet);
                        packetTimesUs.add(info.presentationTimeUs);
                        encodedBytes += packet.length;
                    }
                    outputEos = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    encoder.releaseOutputBuffer(outputIndex, false);
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    encodedFormat = encoder.getOutputFormat();
                    System.out.println("encoded_format=" + encodedFormat);
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                    outputs = encoder.getOutputBuffers();
                }
            }
            if (!outputEos || encodedFormat == null || packets.isEmpty()) {
                throw new IllegalStateException("encode incomplete eos=" + outputEos
                        + " format=" + encodedFormat + " packets=" + packets.size());
            }
        } finally {
            if (encoder != null) {
                try { encoder.stop(); } catch (Throwable ignored) {}
                try { encoder.release(); } catch (Throwable ignored) {}
            }
        }
        long encodeElapsedMs = System.currentTimeMillis() - encodeStartedMs;

        String decoderName = findExynosDecoder(mime);
        if (decoderName == null) {
            throw new IllegalStateException("no Exynos decoder for " + mime);
        }
        long decodeStartedMs = System.currentTimeMillis();
        MediaCodec decoder = null;
        int decodedFrames = 0;
        long decodedBytes = 0;
        try {
            decoder = MediaCodec.createByCodecName(decoderName);
            decoder.configure(encodedFormat, null, null, 0);
            decoder.start();
            ByteBuffer[] inputs = decoder.getInputBuffers();
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            int nextPacket = 0;
            boolean inputEos = false;
            boolean outputEos = false;
            long deadline = System.currentTimeMillis() + DEADLINE_MS;
            while (!outputEos && System.currentTimeMillis() < deadline) {
                if (!inputEos) {
                    int inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US);
                    if (inputIndex >= 0) {
                        if (nextPacket < packets.size()) {
                            byte[] packet = packets.get(nextPacket);
                            ByteBuffer input = inputs[inputIndex];
                            input.clear();
                            if (input.capacity() < packet.length) {
                                throw new IllegalStateException("decoder input capacity="
                                        + input.capacity() + " packet=" + packet.length);
                            }
                            input.put(packet);
                            decoder.queueInputBuffer(inputIndex, 0, packet.length,
                                    packetTimesUs.get(nextPacket), 0);
                            nextPacket++;
                        } else {
                            long eosTimeUs = packetTimesUs.get(packetTimesUs.size() - 1) + 1;
                            decoder.queueInputBuffer(inputIndex, 0, 0, eosTimeUs,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        }
                    }
                }

                int outputIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US);
                if (outputIndex >= 0) {
                    if (info.size > 0) {
                        decodedFrames++;
                        decodedBytes += info.size;
                    }
                    outputEos = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    decoder.releaseOutputBuffer(outputIndex, false);
                } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("decoded_format=" + decoder.getOutputFormat());
                }
            }
            if (!outputEos || decodedFrames != requestedFrames) {
                throw new IllegalStateException("decode incomplete eos=" + outputEos
                        + " requestedFrames=" + requestedFrames
                        + " decodedFrames=" + decodedFrames);
            }
        } finally {
            if (decoder != null) {
                try { decoder.stop(); } catch (Throwable ignored) {}
                try { decoder.release(); } catch (Throwable ignored) {}
            }
        }
        long decodeElapsedMs = System.currentTimeMillis() - decodeStartedMs;
        System.out.println("RESULT=PASS roundtrip encoder=" + encoderName
                + " decoder=" + decoderName + " mime=" + mime
                + " size=" + width + "x" + height
                + " inputFrames=" + requestedFrames + " encodedPackets=" + packets.size()
                + " encodedBytes=" + encodedBytes + " decodedFrames=" + decodedFrames
                + " decodedBytes=" + decodedBytes + " encodeElapsedMs=" + encodeElapsedMs
                + " decodeElapsedMs=" + decodeElapsedMs);
    }

    private static int fillYuv420p(ByteBuffer buffer, int width, int height, int frame) {
        int frameSize = width * height * 3 / 2;
        if (buffer.capacity() < frameSize) {
            throw new IllegalStateException("input capacity=" + buffer.capacity()
                    + " frame=" + frameSize);
        }
        for (int row = 0; row < height; row++) {
            for (int col = 0; col < width; col++) {
                buffer.put((byte) ((row + col + frame * 3) & 0xff));
            }
        }
        for (int i = 0; i < width * height / 4; i++) {
            buffer.put((byte) (96 + (frame & 0x1f)));
        }
        for (int i = 0; i < width * height / 4; i++) {
            buffer.put((byte) (160 - (frame & 0x1f)));
        }
        return frameSize;
    }

    private static String findExynosDecoder(String mime) {
        for (MediaCodecInfo info
                : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (info.isEncoder() || !info.getName().startsWith("OMX.Exynos.")) {
                continue;
            }
            for (String type : info.getSupportedTypes()) {
                if (mime.equalsIgnoreCase(type)) {
                    return info.getName();
                }
            }
        }
        return null;
    }
}
