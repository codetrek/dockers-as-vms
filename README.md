# VMs

Long-lived Ubuntu 24.04 containers used as lightweight VMs: each one runs
systemd as PID 1, an sshd, its own Docker daemon, and keeps its state on the
host through bind mounts, so a VM survives being rebuilt from the image.

## Layout

| Path            | Purpose                                                    |
| --------------- | ---------------------------------------------------------- |
| `docker-vm.sh`  | The one entry point; everything below is a subcommand      |
| `scripts/`      | The commands themselves, and what they have in common      |
| `runner-image/` | The image all VMs share: systemd, sshd, docker-ce, tooling |
| `template/`     | Skeleton copied for each new VM, installers included       |
| `<instance>/`   | One VM: Compose file, `data/`, `scripts/`, ssh settings    |

`docker-vm.sh` sources its commands rather than running them, so that a
command and the definitions it leans on — the shape of a VM name, the
directories that belong to this repository rather than to a VM, the bridge's
name and its address plan — share one process and one spelling. Instance
directories are not tracked: `.gitignore` allowlists only the entries above.

## Looking at what is here

```sh
./docker-vm.sh ls
./docker-vm.sh show my-vm
```

```
NAME           ADDRESS      CPUS  MEMORY  STATUS
borgee-dev-vm  172.28.1.3   4     8g      Up 7 days
my-vm          172.28.1.12  2     4g      not created
```

`ls` reads the instances' Compose files and asks Docker about their containers,
so a VM that has never been started lists like any other. `show` adds what one
VM's disk costs, the volume holding its own Docker storage, and the ssh
settings that reach it — which are read back out of the file rather than worked
out again, since what is in the file is what ssh will do.

## Creating a VM

```sh
./docker-vm.sh create my-vm      # add --cpus / --mem / --ip to override
./docker-vm.sh start my-vm
./docker-vm.sh stop my-vm        # keeps the machine; `delete` is what removes it
```

`create` makes the network if needed, copies the template into `my-vm/`, fills
in the container name, hostname and a free address, authorises the host's SSH
identities (`~/.ssh/id_*.pub`, whichever exist) for the `ubuntu` user, and puts
the name within this host's reach. With no identity to authorise it offers to
run `ssh-keygen` for you; pass `--key FILE` — repeatable — to authorise other
public keys instead. It does not start the VM; `start` does that, building the
runner image first on a host that does not have it yet. A name takes lower-case
letters, digits, `-` and `_` and starts with a letter or a digit, which is what
keeps the directory, the Compose project and the VM's volume going by one
spelling.

## Reaching a VM from the host

Once the VM is up:

```sh
ssh my-vm
ping my-vm
curl http://my-vm:3000
```

Three things make that work, and all three are written by `docker-vm.sh sync`,
which `create` and `delete` call for you:

```sh
./docker-vm.sh sync              # after editing an instance by hand
```

`sync` reads the instance directories and rewrites everything from them. There
is no adding a line here and taking one away there — the host's view of the VMs
is a function of the directories that exist, so the same code produces it
whether a VM has just been made, has just been taken away, or somebody edited a
file by hand. That is also what makes it a repair: run it and the files are
right again.

What it writes into `/etc/hosts` and `~/.ssh/config` is fenced between two
markers:

```
# BEGIN docker-vm.sh
# Written by `docker-vm.sh sync` from the instance directories. What sits
# between these markers is replaced whole; what sits outside them is
# left alone.
172.28.1.10	my-vm
# END docker-vm.sh
```

Everything outside the markers is passed through untouched; everything between
them is replaced. A block whose end marker has been deleted by hand would
swallow the rest of the file, so that stops the run instead.

The `/etc/hosts` block is what answers `ping` and `curl` — this host reads
`files` before `dns`, and there is no DNS these names could come from. It is
the only thing written outside the instance directories that needs root.
`create` refuses a name that something outside the block already answers to,
rather than shadowing it.

The `~/.ssh/config` block holds one `Include` line pointing at the instance
directories, and `sync` puts it at the **top** of the file, moving it back
there if it has wandered. The position is not cosmetic: ssh keeps the first
value it obtains for an option, and what sits at the top of an ssh config is
often exactly the settings meant for everything, up to and including a bare
`UserKnownHostsFile /dev/null`.

`<instance>/ssh_config` is what that include reaches: the VM's `HostName`,
`User ubuntu`, the private half of whichever key it authorises, and a
`known_hosts` of its own. `sync` matches the keys in
`<instance>/data/home/ubuntu/.ssh/authorized_keys` against the ones under
`~/.ssh` by fingerprint, so it can rebuild a fragment it did not write rather
than having to remember what `create` chose.

The per-VM `known_hosts` keeps the shared file from collecting entries for
addresses that `delete` hands straight back to the pool, and lets a VM's
remembered key go when the VM does. Note what it cannot do yet: every VM
presents the same sshd host key, baked into `vm-runner:ubuntu.24.04` when
`openssh-server` was installed, so pinning per instance currently pins the same
key several times over. It becomes worth what it costs once the image stops
carrying one. `delete` also runs `ssh-keygen -R` over the shared file for the
name and the address, clearing what was remembered before any of this existed.

Inside the VMs none of this is needed: Docker's own resolver already answers
`ssh ubuntu@my-other-vm` and `ping my-other-vm` between containers on the
shared bridge. It listens inside each container's network namespace, though, so
it is not something the host can reach.

## Deleting a VM

```sh
./docker-vm.sh delete my-vm      # add --yes to skip the confirmation
```

`delete` takes the container down, removes the `my-vm_docker-disk` volume
holding the VM's own Docker storage, deletes `my-vm/` along with everything
under `data/` — the VM's `/root`, `/home`, `/usr/local` and `/opt` — and takes
the name back off the host. It lists all of that and asks before removing
anything; the address goes back into the pool afterwards. Parts of `data/`
belong to root, so the removal goes through `sudo`. What the VMs share — the
bridge, the runner image, the template — is left alone, and so is every
unrelated container on the host: one counts as this VM's only if Compose rooted
its project at `my-vm/`, never by going under the same name. Its disk volume
carries no such mark and is matched by name, which is what still finds it once
the directory and the container are gone; everything matched is listed before
the question is asked. A VM whose directory was deleted by hand leaves its
container, its volume and its host entry behind, and the same command clears
those away too.

## The shared network

All VMs sit on the `vms_vmnet` bridge (`172.28.1.0/24`, gateway `172.28.1.1`),
so they reach each other at fixed addresses. Compose treats it as `external`
because a project declaring only networks is a no-op for `compose up`;
`docker-vm.sh` owns it instead. `create` puts it up by itself, and
`./docker-vm.sh net` does the same thing on its own. Addresses `.2`–`.9` are
left to Docker's dynamic pool, static assignments start at `.10`. To see what
is taken:

```sh
docker network inspect vms_vmnet -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

## Inside a VM

Log in as `ubuntu` (passwordless sudo, member of `docker`) with the key
`create` authorised in `<instance>/data/home/ubuntu/.ssh/authorized_keys`, then
install what you need:

```sh
~/scripts/install_nodejs.sh     # nvm, node, pnpm
~/scripts/install_golang.sh     # go + gopls, dlv, goimports, staticcheck, govulncheck
~/scripts/install_claude.sh
```

`~/scripts` is the instance's own `scripts/`, copied out of the template when
the VM was created and mounted read-only. A VM therefore keeps the installers
it was made with: fixing one in `template/` reaches the VMs made after that,
and the VMs already here are left as they were until their copy is replaced by
hand. `install_golang.sh` unpacks Go into `/usr/local/go`, which `.profile`
only adds to `PATH` at login — log in again after the first run to get `go` on
your path. `/root`, `/usr/local`, `/opt` and `/home` are bind mounts under the
instance's `data/`, so everything installed there survives `compose down` and an
image rebuild; anything installed elsewhere in the filesystem does not.
