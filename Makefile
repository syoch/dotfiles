PROCS = $(shell nproc)
PROCS_n1 = $(shell expr $(PROCS) - 1)

rebuild:
	cd ~/dotfiles; git add .
	sudo nixos-rebuild switch --flake ~/dotfiles -j $(PROCS_n1)

rebuild-hm:
	cd ~/dotfiles; git add .
	nix run home-manager/master -- switch --flake .

edit-secrets:
	nix-shell -p sops --run "sops ./secrets.yaml"

update-keys:
	nix-shell -p sops --run "sops updatekeys ./secrets.yaml"

iso:
	nix build .#iso -j $(PROCS_n1)

upgrade:
	nix flake update
	# $(MAKE) cleanup
	$(MAKE) rebuild-hm
	$(MAKE) cleanup
	$(MAKE) rebuild

cleanup:
	scripts/cleanup
