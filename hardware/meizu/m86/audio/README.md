# Flyme normal-audio ABI boundary

`LegacyAudioAbiContract.h` is the reviewed input contract for the source-built
32-bit wrapper. The wrapper is the default `audio.primary.m86.so` producer;
the locked 32-bit Flyme HAL is installed as the private
`audio.primary.m86.flyme.so` input, and its 64-bit copy is inventory-only.

The wrapper must own a public Android 10 `audio_hw_device` and separately hold
the raw Flyme device. It must do the same for every returned output and input
stream; returning a raw Flyme stream would recreate the `0x2` metadata crash
even if the device struct were translated correctly. Close callbacks must
receive the original raw stream pointer.

The first switch build keeps the narrow AudioFlinger caller and consumes its
exact private parameter in the wrapper. The global compatibility patches stay
active until normal-audio and Hi-Fi device gates prove an equivalent
device-owned path; their retirement is a separate cleanup step.

The route bridge deliberately preserves the legacy Android 2.0 capability.
Android 10 then sends `routing=N` through the output stream's
`set_parameters`, exactly as the known-good direct Flyme HAL path does. The
wrapper may retain a defensive `create_audio_patch` translation for callers
that bypass the normal capability check, but it must forward that key to the
active output stream; it must never use the Flyme device-level callback for
routing. Advertising API 3.0/current or routing through the device callback
leaves Flyme at `route none`, so the codec DAPM path stays off and PCM writes
return `Device or resource busy`.
