#!/bin/sh
set -eu

export DISPLAY=:99
export XMODIFIERS=@im=ibus
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus

Xvfb "$DISPLAY" -screen 0 800x600x24 +extension GLX >/tmp/zaniah-xvfb.log 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
sleep 2

gsettings set org.freedesktop.ibus.general preload-engines "['mozc-on']"
gsettings set org.freedesktop.ibus.general engines-order "['mozc-on']"
gsettings set org.freedesktop.ibus.general enable-by-default true
ibus-daemon --daemonize --xim --desktop=none --panel=disable --emoji-extension=disable
sleep 3

ruby examples/native_ime.rb
