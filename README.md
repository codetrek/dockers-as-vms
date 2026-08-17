# VMs

Long-lived Ubuntu 24.04 containers used as lightweight VMs: each one runs
systemd as PID 1, an sshd, its own Docker daemon, and keeps its state on the
host through bind mounts, so a VM survives being rebuilt from the image.

## Layout

| Path            | Purpose                                                          |
| --------------- | ---------------------------------------------------------------- |
| `runner-image/` | The image all VMs share: systemd, sshd, docker-ce, dev tooling    |
| `scripts/`      | Toolchain installers, mounted read-only at `~/scripts` in each VM |
| `template/`     | Skeleton copied for each new VM                                   |
| `create_vm.sh`  | Creates a VM from the template                                    |
| `delete_vm.sh`  | Deletes a VM and everything it owns                               |
| `vmnet.sh`      | Creates the bridge network the VMs share                          |
| `<instance>/`   | One directory per VM: `docker-compose.yml` plus its `data/`       |

Instance directories are not tracked — `.gitignore` allowlists only the entries
above.

## Creating a VM

```sh
./create_vm.sh my-vm                       # add --cpus / --mem / --ip to override
cd my-vm && docker compose up -d --build
```

`create_vm.sh` creates the network if needed, copies the template into `my-vm/`,
fills in the container name, hostname and a free address, and authorises the
host's SSH identities (`~/.ssh/id_*.pub`, whichever exist) for the `ubuntu`
user. With no identity to authorise it offers to run `ssh-keygen` for you; pass
`--key FILE` — repeatable — to authorise other public keys instead. It does not
start the VM. A name takes lower-case letters, digits, `-` and `_` and starts
with a letter or a digit, which is what keeps the directory, the Compose project
and the VM's volume going by one spelling.

## Deleting a VM

```sh
./delete_vm.sh my-vm                       # add --yes to skip the confirmation
```

`delete_vm.sh` takes the container down, removes the `my-vm_docker-disk` volume
holding the VM's own Docker storage, and deletes `my-vm/` along with everything
under `data/` — the VM's `/root`, `/home`, `/usr/local` and `/opt`. It lists all
of that and asks before removing anything; the address goes back into the pool
afterwards. Parts of `data/` belong to root, so the removal goes through `sudo`.
What the VMs share — the bridge, the runner image, `scripts/` — is left alone,
and so is every unrelated container on the host: one counts as this VM's only if
Compose rooted its project at `my-vm/`, never by going under the same name. Its
disk volume carries no such mark and is matched by name, which is what still
finds it once the directory and the container are gone; everything matched is
listed before the question is asked. A VM whose directory was deleted by hand
leaves its container and its volume behind, and the same command clears those
away too.

## The shared network

All VMs sit on the `vms_vmnet` bridge (`172.28.1.0/24`, gateway `172.28.1.1`),
so they reach each other at fixed addresses. Compose treats it as `external`
because a project declaring only networks is a no-op for `compose up`;
`vmnet.sh` owns it instead and `create_vm.sh` calls it. Addresses `.2`–`.9` are
left to Docker's dynamic pool, static assignments start at `.10`. To see what is
taken:

```sh
docker network inspect vms_vmnet -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

## Inside a VM

Log in as `ubuntu` (passwordless sudo, member of `docker`) with the key
`create_vm.sh` authorised in `<instance>/data/home/ubuntu/.ssh/authorized_keys`,
then install what you need:

```sh
~/scripts/install_nodejs.sh     # nvm, node, pnpm
~/scripts/install_golang.sh     # go + gopls, dlv, goimports, staticcheck, govulncheck
~/scripts/install_claude.sh
```

`install_golang.sh` unpacks Go into `/usr/local/go`, which `.profile` only adds
to `PATH` at login — log in again after the first run to get `go` on your path.
`/root`, `/usr/local`, `/opt` and `/home` are bind mounts under the instance's
`data/`, so everything installed there survives `compose down` and an image
rebuild; anything installed elsewhere in the filesystem does not.
