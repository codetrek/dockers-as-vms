# VMs

Long-lived Ubuntu 24.04 containers used as lightweight VMs: each one runs
systemd as PID 1, an sshd and its own Docker daemon, and keeps its state on the
host, so a VM survives being rebuilt from the image. An init system and a
nested Docker daemon need a privileged container — `privileged: true`,
`cgroup: host`, seccomp and AppArmor unconfined — so a VM here is a
convenience, not a boundary: root inside one is root on this host.

## Layout

| Path            | Purpose                                                    |
| --------------- | ---------------------------------------------------------- |
| `docker-vm.sh`  | The one entry point; everything below is a subcommand      |
| `scripts/`      | The commands themselves, and what they have in common      |
| `runner-image/` | The image all VMs share: systemd, sshd, docker-ce, tooling |
| `template/`     | Skeleton copied for each new VM, installers included       |
| `<instance>/`   | One VM: Compose file, `data/`, `scripts/`, ssh settings    |

`docker-vm.sh` sources its commands rather than running them, so that a command
and the definitions it leans on — the shape of a VM name, the directories that
belong to this repository rather than to a VM, the bridge's name and its
address plan — share one process and one spelling. It resolves its own path
first, so a symlink to it from somewhere on `$PATH` still finds the template,
the instances and `scripts/` beside the real file. Instance directories are not
tracked: `.gitignore` allowlists only the entries above.

## Looking at what is here

```sh
./docker-vm.sh ls
./docker-vm.sh show my-vm
```

```
NAME           ADDRESS      CPUS  MEMORY  STATUS
borgee-dev-vm  172.28.1.10  4     8g      Up 7 days
my-vm          172.28.1.11  2     4g      not created
```

`ls` reads the instances' Compose files and asks Docker about their containers,
so a VM that has never been started lists like any other. `show` adds what one
VM's directory costs, the volume holding its own Docker storage, and the ssh
settings that reach it — which are read back out of the file rather than worked
out again, since what is in the file is what ssh will do. Measuring the
directory goes through `sudo` once the VM has been up: Docker creates the
bind-mount targets under `data/` as root, and an unprivileged `du` would stop
at them and undercount.

## Creating a VM

```sh
./docker-vm.sh create my-vm --start
```

| Option       | Effect                                                          |
| ------------ | --------------------------------------------------------------- |
| `--ip ADDR`  | Static address; the lowest free one is picked when omitted      |
| `--cpus N`   | CPU limit, asked for when omitted (default `2`)                 |
| `--mem SIZE` | Memory limit with a unit, asked for when omitted (default `4g`) |
| `--key FILE` | Public key to authorise for `ubuntu`, repeatable                |
| `--start`    | Bring the VM up once it is made                                 |

`create` makes the network if needed, copies the template into `my-vm/`, fills
in the container name, hostname and a free address, authorises the host's SSH
identities for the `ubuntu` user, and puts the name within this host's reach.
It leaves the VM stopped unless `--start` is given, which hands it straight to
`start`.

Sizing is the one thing worth thinking about per VM, so `--cpus` and `--mem`
are asked for rather than silently defaulted: on a terminal `create` prompts
`CPUs [2]:` and `Memory [4g]:`, and re-asks whatever it cannot use. A run with
nobody to ask takes the defaults instead of blocking. The unit on a memory
limit is not optional either way — Docker reads a bare number as a count of
bytes, and Compose writes such a value out without a word, leaving the failure
to a `compose up` long afterwards.

The identities authorised by default are the ones ssh(1) offers by itself —
`id_rsa`, `id_ecdsa`, `id_ecdsa_sk`, `id_ed25519`, `id_ed25519_sk`, `id_xmss`
and `id_dsa`, whichever of them have a `.pub` under `~/.ssh` — all of them,
since picking one out of several would only be guessing which. A key kept under
any other name is not among them: name it with `--key`, which is repeatable and
takes the place of that default set. With no identity to authorise at all,
`create` offers to run `ssh-keygen` rather than make a VM nobody can log into.

A name takes lower-case letters, digits, `-` and `_` and starts with a letter
or a digit, which is what keeps the directory, the Compose project and the VM's
volume going by one spelling. Four names are spoken for: `runner-image`,
`scripts`, `template`, and whatever this directory itself is called — a VM by
that last name would take the repository's own Compose project name and mix the
two up in every label Docker keeps. A name that something outside our block in
`/etc/hosts` already answers to is refused as well, rather than shadowed.

## Starting and stopping

```sh
./docker-vm.sh start my-vm
./docker-vm.sh stop my-vm
```

`start` brings the VM up, building `vm-runner:ubuntu.24.04` first on a host
that does not have it yet, so a VM taken from a fresh clone comes up on the
same command as one that has run here for months. `stop` takes a VM down
without taking it apart: the container and its disk stay where they are, and
`start` brings the same machine back. Both pin Compose to the instance's own
project and file, so a stray `COMPOSE_PROJECT_NAME` or `COMPOSE_FILE` in the
environment cannot aim them at another stack. The service is
`restart: unless-stopped`, so a VM that was up returns with the host's Docker
daemon while one that was stopped stays stopped.

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
./docker-vm.sh sync
```

`sync` reads the instance directories and rewrites everything from them. There
is no adding a line here and taking one away there — the host's view of the VMs
is a function of the directories that exist, so the same code produces it
whether a VM has just been made, has just been taken away, or somebody edited a
file by hand. That is also what makes it a repair: run it and the files are
right again. Run it after moving this repository too: the `Include` line and
each instance's `known_hosts` are written as absolute paths, and ssh passes
over an include that matches nothing without a word, so a move otherwise leaves
the names resolving as before while every VM's ssh settings have quietly gone.

What it writes into `/etc/hosts` and `~/.ssh/config` is fenced between two
markers:

```
# BEGIN docker-vm.sh
# Written by `docker-vm.sh sync` from the instance directories.
# What sits between these markers is replaced whole; what sits
# outside them is left alone.
172.28.1.10	my-vm
# END docker-vm.sh
```

Everything outside the markers is passed through untouched; everything between
them is replaced. A block whose end marker has been deleted by hand would
swallow the rest of the file, so that stops the run instead.

The `/etc/hosts` block is what answers `ping` and `curl` — this host reads
`files` before `dns`, and there is no DNS these names could come from. It is
the only thing written outside the instance directories that needs root.

The `~/.ssh/config` block holds one `Include` line pointing at the instance
directories, and `sync` puts it at the **top** of the file, moving it back
there if it has wandered. The position is not cosmetic: ssh keeps the first
value it obtains for an option, and what sits at the top of an ssh config is
often exactly the settings meant for everything, up to and including a bare
`UserKnownHostsFile /dev/null`.

`<instance>/ssh_config` is what that include reaches. It gives the VM's
`HostName`, `User ubuntu`, an `IdentityFile` for the private half of each key
it authorises, and `IdentitiesOnly yes` so that ssh offers those rather than
working through everything the agent holds — sshd hangs up after six tries. Its
`Host` line carries the address as well as the name, so reaching a VM by
address gets the same settings instead of falling back on the shared files. It
pins a `known_hosts` of its own under `StrictHostKeyChecking accept-new`: the
first key a VM presents is remembered without a question, and only a key that
changes afterwards is refused. `sync` matches the keys in
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
./docker-vm.sh delete my-vm
./docker-vm.sh delete my-vm --yes   # nothing asked; required off a terminal
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
left to Docker's dynamic pool, static assignments start at `.10`.

`./docker-vm.sh ls` is what says which of those are taken, and it is the list
`create` goes by: an address belongs to a VM for as long as its Compose file
names it, whether or not anything is attached to the bridge at the time, which
is what keeps a VM that is down — the state `create` leaves one in — from
losing its address to the next one made. `--ip` is taken as given rather than
checked against that list, so a duplicate chosen by hand surfaces at
`compose up`. For what is on the bridge right now, VM or not:

```sh
docker network inspect vms_vmnet -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

## Inside a VM

Log in as `ubuntu` (passwordless sudo, member of `docker`) with the key
`create` authorised in `<instance>/data/home/ubuntu/.ssh/authorized_keys`, then
install what you need:

```sh
~/scripts/install_nodejs.sh     # nvm, node 24, pnpm through corepack
~/scripts/install_golang.sh     # go + gopls, dlv, goimports, staticcheck, govulncheck
~/scripts/install_claude.sh
```

`~/scripts` is the instance's own `scripts/`, copied out of the template when
the VM was created and mounted read-only. A VM therefore keeps the installers
it was made with: fixing one in `template/` reaches the VMs made after that,
and the VMs already here are left as they were until their copy is replaced by
hand. `install_golang.sh` unpacks Go into `/usr/local/go`, which `.profile`
only adds to `PATH` at login — log in again after the first run to get `go` on
your path.

What outlives the container is what is mounted into it. `/root`, `/home`,
`/usr/local` and `/opt` are bind mounts under the instance's `data/`, which is
also where the host can read them. `/var/lib/docker` is the
`<instance>_docker-disk` volume, so the images, containers and build cache of
the VM's own Docker daemon survive `compose down` as well — `delete` is what
takes those away. `/tmp`, `/run` and `/run/lock` are tmpfs and go with each
stop, and anything installed anywhere else belongs to the image layer and goes
with a rebuild.
