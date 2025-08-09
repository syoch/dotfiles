SSH_KEY ?= id_syoch

all:

keys.txt: $(SSH_KEY)
	nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $< > $@"
all: keys.txt

keys.pub.txt: keys.txt
	nix-shell -p age --run "age-keygen -y $< > $@"
all: keys.pub.txt

install: keys.txt $(SSH_KEY)
	mkdir -p ~/.config/sops/age
	cp keys.txt ~/.config/sops/age/keys.txt
	cp $(SSH_KEY) ~/.config/sops/age/id_syoch
all: install