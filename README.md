# sshplex

## Overview

`sshplex` is just another SSH multiplexer that sends commands to multiple
target hosts and gathers their outputs.

You know, the one you've written countless times yourself. This is my most
recent attempt that scratches my particular itches and replaces previous
efforts.

## Features

* Can operate in either `exec` and `shell` mode, whichever suits your needs

* Pure Ruby, no linking to `libssh` or `libcrypto`

* That's it

## Shell mode

When a SSH channel is in `shell` mode you don't know when a command is
complete. Instead, you watch the output for your shell's prompt to reappear.
With a regex. This is somewhat fragile.

## Requirements

Ruby, Bundler. See `Gemfile`

## Thanks

Thanks to [Jamis Buck](https://github.com/jamis) and contributors for
[`Net::SSH`](https://github.com/net-ssh/net-ssh).

## Example

```
% bundle exec ./sshplex -A mon.zomo.co.uk ns0.zomo.co.uk
sshplex% df -h
[mon.zomo.co.uk] # exec: df -h
[ns0.zomo.co.uk] # exec: df -h
[ns0.zomo.co.uk] Filesystem      Size    Used   Avail Capacity  Mounted on
[ns0.zomo.co.uk] /dev/vtbd0p2    9.2G    6.3G    2.1G    75%    /
[ns0.zomo.co.uk] devfs           1.0K    1.0K      0B   100%    /dev
[ns0.zomo.co.uk] # exit: 0
[mon.zomo.co.uk] Filesystem      Size    Used   Avail Capacity  Mounted on
[mon.zomo.co.uk] /dev/vtbd0p3    108G     75G     24G    75%    /
[mon.zomo.co.uk] devfs           1.0K    1.0K      0B   100%    /dev
[mon.zomo.co.uk] # exit: 0
```

## License

Relesed under MIT license, see LICENSE. Non-warranty in there too.

## Author

Jon Stuart, Zikomo Technology, 2023
