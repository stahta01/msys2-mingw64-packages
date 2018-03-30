pacman -S --asdeps --needed --noconfirm git

# My internet connection is too bad to clone using the sf.net URL.
# But, it can clone https://github.com/stahta01/zinjai-ide.git URL

git clone --bare --single-branch https://github.com/stahta01/zinjai-ide.git zinjai && \
cd zinjai && \
git remote add origin0 https://github.com/stahta01/zinjai-ide.git && \
git remote set-url origin git://git.code.sf.net/p/zinjai/code  && \
git fetch origin
git remote remove origin0
git fetch --all --prune
