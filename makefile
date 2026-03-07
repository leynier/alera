.PHONY: update-refs

# Update all reference projects (git submodules) to their latest remote commits
update-refs:
	git submodule update --init --recursive --remote --merge
