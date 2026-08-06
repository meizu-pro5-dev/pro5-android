# M86 case-sensitive kernel overlay

The locked Meizu kernel contains 12 Netfilter pairs whose names differ only by
case. They cannot coexist in the main working tree on the default macOS
filesystem. `upper/` and `lower/` retain all 24 files from commit
`67699d9442a9557eca24ba7a489ffa1b0601e806` in separate directory namespaces.

`remote/install-local-trees.sh` verifies `SHA256SUMS` and installs each file at
the path below its variant directory after the ordinary kernel rsync. Do not
rename these public headers or Kbuild sources; update the corresponding overlay
copy and hash if a later port change genuinely needs to modify one.
