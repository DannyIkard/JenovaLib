#!/bin/bash
GetScreenWidth(){
  stty size 2>/dev/null | cut -d " " -f 2
}

Status(){
  local check=$?
  local cols=$(GetScreenWidth)
  [ "$cols" ] || cols=80
  local scol=$(($cols - 7))
    if [ $check = 0 ]; then
      if [ "$1" = "Success" ]; then Success=1; fi
      echo -e "\033[${scol}G\033[38;5;22;1mOK\033[0;39m"
    else
      if [ $@ ]; then
        if [ "$1" = "Success" ]; then
          Success=0
        else
          $@
        fi
      else
        echo -e "\033[${scol}G\033[1;31mError\033[0;39m"
      fi
    fi
}

StatusOK(){
  local cols=$(GetScreenWidth)
  [ "$cols" ] || cols=80
  local scol=$(($cols - 7))
  echo -e "\033[1A\033[${scol}G\033[38;5;22;1mOK\033[0;39m"
}

StatusError(){
  local cols=$(GetScreenWidth)
  [ "$cols" ] || cols=80
  local scol=$(($cols - 7))
  echo -e "\033[1A\033[${scol}G\033[1;31mError\033[0;39m"
}

Separator(){
  if [ $1 ]; then local sepchar="$1"; else local sepchar=" "; fi
  local cols=$(GetScreenWidth)
  [ "$cols" ] || cols=80
  for x in $(seq 1 $cols); do
    echo -n "$sepchar"
  done && echo ""
}

EchoBold(){
  if [ "$1" = "-n" ]; then shift; echo -en "\033[1m$@\033[0m"; else echo -e "\033[1m$@\033[0m"; fi
}

EchoRed(){
  if [ "$1" = "-n" ]; then shift; echo -en "\033[1;31m$@\033[0m"; else echo -e "\033[1;31m$@\033[0m"; fi
}

EchoGreen(){
  if [ "$1" = "-n" ]; then shift; echo -en "\033[38;5;22;1m$@\033[0m"; else echo -e "\033[38;5;22;1m$@\033[0m"; fi
}

Title(){
  echo -en "\033[7;1m"
  local cols=$(GetScreenWidth)
  [ "$cols" ] || cols=80
  (( Spacer = cols - ${#1} ))
  (( Spacer = Spacer / 2 ))
  for x in $(seq 1 $Spacer); do
    echo -n " "
  done
  echo -en "$1"
  local cols=$(GetScreenWidth)
  [ "$cols" ] || cols=80
  for x in $(seq 1 $Spacer); do
    echo -n " "
  done && echo -e "\033[0m"
}

Longline(){
  cols=$(GetScreenWidth); [ "$cols" ] || cols=80
  echo -e "$@" | fold -sw$cols
}

AddIfDoesntExist(){
  if ! cat $2 | grep "$1"; then
    sudo su -c "echo \"$1\">>$2" root
  fi
}

SudoRequired(){
  if ! command -v sudo >/dev/null; then
    EchoRed "  Please install sudo to use this script."
    EchoBold "`Longline  'As root, do \"apt-get install sudo\" then \"adduser <username> sudo\" and then log out and log back in.'`"
    exit 1
  fi
  clear
  EchoRed "This script requires sudo."
  echo -n "Enter the "
  sudo printf ""
  clear
}

Success="0"
JustFail="0"
Exit(){
  if [ "$JustFail" = "0" ]; then
    JustFail="1"
    if [ "$Success" = "1" ]; then
      if [ "$2" != "NoPrompt" ]; then
        EchoGreen "  Press enter to exit..."
        read LINE
        exit 0
      fi
    else
      EchoRed "  Script failure."
      Longline "  $1"
      EchoBold -n "  Press enter to exit..."
      read LINE
      exit 1
    fi
  fi
}

SuccessExit(){
  if [ $? = 0 ]; then Success="1"; fi
  exit 0
}

PIDCheck(){
  PIDDir="$1"
  sudo mkdir $PIDDir 2>/dev/null
  PIDs="$(sudo find -L "$PIDDir" -type f)"
  if [ "$PIDs" != "" ]; then
    if [ "$Quiet" = 0 ]; then EchoRed "Stopping old processes"; fi
    echo "$PIDs" | while read PID; do
      PID="`echo $PID | rev | cut -d \"/\" -f1 | rev`"
      killtree() {
        local _pid=$1
        local _sig=${2:-15}
        sudo kill -stop ${_pid} # needed to stop quickly forking parent from producing children between child killing and parent killing
        for _child in $(ps -o pid --no-headers --ppid ${_pid}); do
          killtree ${_child} ${_sig}
        done
        kill -${_sig} ${_pid}
       }
       killtree $PID
      sudo rm -f $PIDDir/$PID 2>/dev/null
    done
    sleep 1
  fi
  sudo touch $PIDDir/$$ 2>/dev/null
}

InstallPkg(){
  if [ $2 ]; then 
    if [ "${2,,}" = "--wait" ]; then Wait=1; shift; fi
    if [ "${2,,}" = "--exit" ]; then Wait=0; shift; fi
  else
    Wait=0
  fi
  if [ $2 ]; then TempFile="$2"; else TempFile="/dev/shm/apt-get_stout.tmp"; fi
  echo -n "  Checking $1"
  if dpkg-query -W --showformat='${Status}\n' $1 2>/dev/null | grep "install ok installed" >/dev/null; then
    printf "\n"
    StatusOK
  else
    sudo rm -f $TempFile
    printf "%s" "...  Installing"
    sudo apt-get -y install $1 1>$TempFile 2>&1 &
    printf "\n"
    while ps -ef | grep "apt-get" | grep -v grep >/dev/null; do
      local cols=$(GetScreenWidth)
      [ "$cols" ] || cols=80
      local LOGLINE="`sudo tail -1 $TempFile`"
      if [ "$LOGLINE" ]; then
        if echo "$LOGLINE" | grep 'Unable to lock the administration directory' >/dev/null; then
          if [ "$Wait" = "1" ]; then
            EchoRed "\r\033[K  Aptitude is busy.  Waiting..."
            sleep 1
          else
            StatusError
            EchoRed "\r\033[K  Aptitude is busy."
            EchoBold "`Longline \"  Perhaps you are downloading software updates.  Please wait, or if you believe Aptitude exited badly then restart your computer.\"`"
            exit 1
          fi
        fi
        EchoGreen -n "\r\033[K    `echo \"$LOGLINE\" | cut -c 1-$(( cols - 4 ))`"
      fi
      sleep .3
    done
    ExitCode="$?"
    echo -en "\r\033[K"
    if [ "$ExitCode" -ne "0" ]; then
      EchoRed "\n  apt-get exited with code $?"
    else
      StatusOK
    fi
    sudo rm -f $TempFile
  fi
}




