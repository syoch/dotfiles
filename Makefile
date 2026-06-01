PROCS = $(shell nproc)
PROCS_n1 = $(shell expr $(PROCS) - 1)

SV01_USER := syoch
SV01_HOST := 100.96.100.1
SV01_SECRETS := ./components/host/sv01/secrets-sv01.yaml

SYOCH_NIX_USER := syoch
SYOCH_NIX_HOST := syoch-nix
SYOCH_NIX_SECRETS := ./components/host/syoch-nix/secrets.yaml

rebuild-sv01:
	nixos-rebuild switch --flake .#sv01 \
		--sudo \
		--target-host $(SV01_USER)@$(SV01_HOST) \

rebuild:
	cd ~/dotfiles; git add .
	sudo nixos-rebuild switch --flake ~/dotfiles -j $(PROCS_n1)

rebuild-hm:
	cd ~/dotfiles; git add .
	nix run home-manager/master -- switch --flake .

edit-secrets:
	EDITOR="code --wait" nix-shell -p sops --run "sops components/host/syoch-nix/secrets.yaml"

edit-secrets-sv01:
	EDITOR="code --wait" nix-shell -p sops --run "sops components/host/sv01/secrets.yaml"

update-keys:
	nix-shell -p sops --run "sops updatekeys components/host/syoch-nix/secrets.yaml"

update-keys-sv01:
	nix-shell -p sops --run "sops updatekeys ./components/host/sv01/secrets.yaml"

iso:
	nix build .#iso -j $(PROCS_n1)

upgrade:
	nix flake update
	$(MAKE) rebuild-hm
	$(MAKE) rebuild

cleanup:
	scripts/cleanup

droid-sync-update-adb:
	adb push scripts/update-nix-on-droid /data/data/com.termux.nix/files/home/update.sh
	adb shell chown 10007:10007 /data/data/com.termux.nix/files/home/update.sh

droid-sync-dotfiles-adb:
	tar czf dotfiles.tgz --exclude=dotfiles.tgz --exclude=winapps --exclude=.git --exclude=.direnv .
	adb push dotfiles.tgz /data/local/tmp/dotfiles.tgz
	adb shell su -c cp /data/local/tmp/dotfiles.tgz /data/data/com.termux.nix/files/home/dotfiles.tgz
	adb shell su -c chown 10007:10007 /data/data/com.termux.nix/files/home/dotfiles.tgz