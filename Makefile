SHELL := /bin/bash
.PHONY: install test shellcheck clean

install:
	./install.sh

test:
	bash tests/run_tests.sh

shellcheck:
	shellcheck -x install.sh bin/glm-claude tests/*.sh

clean:
	@read -r -p "Remove ~/.glm-claude (proxy, venv, stored API key)? [y/N] " ans; \
	case "$$ans" in \
	  [yY]*) rm -rf "$$HOME/.glm-claude" && echo "removed ~/.glm-claude"; \
	         rm -f "$$HOME/.local/bin/glm-claude" && echo "removed launcher symlink";; \
	  *) echo "aborted";; \
	esac
