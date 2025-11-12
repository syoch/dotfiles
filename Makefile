PROCS = $(shell nproc)
PROCS_n1 = $(shell expr $(PROCS) - 1)

rebuild:
	cd ~/dotfiles
	git add .
	sudo nixos-rebuild switch --flake ~/dotfiles -j $(PROCS_n1)

rebuild-hm:
	cd ~/dotfiles
	git add .
	nix run home-manager/master -- switch --flake .

upgrade:
	sudo nixos-rebuild switch --flake ~/dotfiles -j $(PROCS_n1) --upgrade

edit-secrets:
	nix-shell -p sops --run "sops ./secrets.yaml"

update-keys:
	nix-shell -p sops --run "sops updatekeys ./secrets.yaml"

iso:
	nix build .#iso -j $(PROCS_n1)

cleanup:
	for l in /nix/var/nix/gcroots/auto/*; do p=`readlink $l`; stat $p >/dev/null 2>&1 || { sudo rm  $l} && echo "Saved $p"; true; done
	nix store gc
	nix-collect-garbage -d
	nix store optimise