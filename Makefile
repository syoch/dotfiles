PROCS = $(shell nproc)
PROCS_n1 = $(shell expr $(PROCS) - 1)

rebuild:
	cd ~/dotfiles
	git add .
	sudo nixos-rebuild switch --flake ~/dotfiles -j $(PROCS_n1)

edit-secrets:
	nix-shell -p sops --run "sops ./secrets.yaml"

update-keys:
	nix-shell -p sops --run "sops updatekeys ./secrets.yaml"
