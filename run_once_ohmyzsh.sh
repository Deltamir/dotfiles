#!/bin/sh

if [ ! -d "{{ .chezmoi.homeDir }}/.oh-my-zsh" ]; then
  git clone https://github.com/ohmyzsh/ohmyzsh.git "{{ .chezmoi.homeDir }}/.oh-my-zsh"
fi
