# m86 legacy libgatekeeper

This directory vendors `platform/system/gatekeeper` at AOSP
`95a65511bd48ea8da24a2ecb97e6196ce23503b4` (`android-10.0.0_r41`) under
Apache-2.0. The resulting `libgatekeeper_m86.so` is installed as
`/vendor/lib64/gatekeeper-legacy/libgatekeeper.so` and is resolved only by the
m86 gatekeeper service through its `LD_LIBRARY_PATH`, keeping the Flyme
`gatekeeper.m86.so` blob on the A10 C++ ABI it was built against.
