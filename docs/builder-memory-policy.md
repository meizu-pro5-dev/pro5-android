# Builder memory safety policy

The remote Android builder runs inside a 60 GiB cgroup even when the host has
substantially more free RAM. Every Android, standalone-kernel, and TWRP build
therefore executes `remote/prepare-builder-memory.sh` before compilation.

The preflight reads cgroup-v2 `memory.current`, `memory.max`, `memory.stat`, and
`memory.events`. It reserves a profile-specific safety margin, derives a safe
job count from the non-reclaimable footprint, caps it at eight, and fails closed
when one job plus the reserve cannot fit. When clean build-output page cache is
already consuming at least 70% of the cgroup, it calls
`remote/release-build-cache.py`. That helper applies
`POSIX_FADV_DONTNEED` only to regular output files of at least 1 MiB; it does not
delete, truncate, or rewrite build inputs or products.

Android `systemimage`, `testzip`, and `bacon` builds also force dex2oat boot-image
compilation to one worker and generate the ARM and ARM64 boot artifacts as two
serial Ninja edges. Normal compilation resumes at the calculated parallelism
after those memory peaks are complete.

Each serialized boot-ART edge gets at most two attempts. Before and after every
attempt, the worker appends cgroup memory current/stat/events plus host
`MemAvailable`, `CommitLimit`, and `Committed_AS` to `BUILD-MEMORY.txt`, and it
retains a separate attempt log while also streaming that log into the main build
log. A first attempt is retried only when one log line reports both `Failed
anonymous mmap` and `Cannot allocate memory`; the worker then advises clean
output pages away, waits briefly, and retries the same exact edge once. All
other failures, and any second-attempt failure, preserve the Ninja exit status
and stop the build. This is a bounded recovery for an observed but not yet
attributed transient anonymous-mmap failure, not a claim that cgroup capacity,
host commit, or VMA count caused it.

Each successful artifact directory includes `BUILD-MEMORY.txt`, and build
metadata records requested versus effective jobs. A missing cgroup input, an
unsafe budget, a cache-release error, or an invalid derived job count stops the
build before compilation.
