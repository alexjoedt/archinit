Refactor this repository from a over engineered all-in one script to splt it up in self-contained small independent scripts.

Do not source from "${ARCHINIT_HOME}/lib

- simple-install.sh # installs only pacman packages from the package list
- install_aur.sh # installs only aur packages from the aur-package list
- scripts/enable_user_services.sh # chekcks which user services are available and the user can decide which can be enabled
- ensure_zsh.sh