.PHONY: install config

config: .config

install: config
	ruby setup.rb install

.config: setup.rb
	ruby setup.rb config
