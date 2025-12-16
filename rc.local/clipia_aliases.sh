# enable clipia

# Need to find way to make this a binary w/o having to activate

if [ -f ~/.local/share/pipx/venvs/clipea-cli/bin/activate  ]; then
    . ~/.local/share/pipx/venvs/clipea-cli/bin/activate 
    alias \?\?=clipea
else
    echo Clipia not installed
fi

