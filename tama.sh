#!/bin/sh
#
# tama
# a fetch in pure POSIX
# :)
#

# suppress errors
exec 2>/dev/null
set --
eq() { # equals | [ a = b ] with globbing
	case $1 in
		$2) ;;
		*) return 1;;
	esac
}

## de
wm=$XDG_CURRENT_DESKTOP
[ "$wm" ] || wm=$DESKTOP_SESSION

## distro
for os in /etc/os-release /usr/lib/os-release; do
	[ -f $os ] && . $os && break
done

if [ -e /proc/$$/comm ]; then
	## terminal
	while [ ! "$term" ]; do
		# loop over lines in /proc/pid/status until it reaches PPid
		# then save over to a variable and exit the file
		while read -r line; do
			eq "$line" 'PPid*' && ppid=${line##*:?} && break
		done < "/proc/${ppid:-$PPID}/status"

		# do not do an infinite loop
		[ "$pppid" = "$ppid" ] && break
		pppid=$ppid

		# get name of binary
		read -r name < "/proc/$ppid/comm"

		case $name in
			*sh|"${0##*/}") ;;  # skip shells
			*[Ll]ogin*|*init*|*systemd*) break;;  # exit when the top is reached
			# anything else can be assumed to be the terminal
			*) term=$name
		esac
	done

	## wm / de
	[ ! "$wm" ] &&
		# loop over all processes and check the binary name
		for i in /proc/*/comm; do
			read -r c < "$i"
			case $c in
				*bar*) ;;
				awesome|xmonad*|qtile|sway|i3|[bfo]*box|*wm*) wm=${c%%-*}; break;;
			esac
		done

	## memory
	# loop over lines in /proc/meminfo until it reaches MemTotal,
	# then convert the amount (second word) from KB to MB
	while read -r line; do
		eq "$line" 'MemTotal*' && set -- $line && break
	done < /proc/meminfo
	mem="$(( $2 / 1000 ))MB"

	## processor
	while read -r line; do
		case $line in
			vendor_id*) vendor="${line##*: } ";;
			model\ name*) cpu=${line##*: }; break;;
		esac
	done < /proc/cpuinfo

	## uptime
	IFS=. read -r uptime _ < /proc/uptime
	d=$((uptime / 60 / 60 / 24))
	up=$(printf %02d:%02d $((uptime / 60 / 60 % 24)) $((uptime / 60 % 60)))
	[ "$d" -gt 0 ] && up="${d}d $up"

	## kernel
	read -r _ _ version _ < /proc/version
	kernel=${version%%-*}
	eq "$version" '*Microsoft*' && ID="fake $ID"

	## motherboard / laptop
	read -r model < /sys/devices/virtual/dmi/id/product_name
	# invalid model handling
	case $model in
		# alternate file with slightly different info
		# on my laptop it has the device model (instead of 'asus vivobook')
		# which is fine i guess
		'System '*|'Default '*)
			read -r model < /sys/devices/virtual/dmi/id/board_name
	esac

	## packages
	# clean environment, then make every file in the dir an argument,
	# then save the argument count to $pkgs
	set --
	# kiss, pacman, dpkg, xbps, portage/pkg
	for i in '/var/db/kiss/installed/*'  '/var/lib/pacman/local/[0-9a-z]*' \
	'/var/lib/dpkg/info/*.list'  '/var/db/xbps/.*'  '/var/db/pkg/*/*'; do
		set -- $i
		[ $# -gt 1 ] && pkgs=$# && break
	done

	read -r host < /proc/sys/kernel/hostname
elif [ -f /var/run/dmesg.boot ]; then
	# both openbsd and freebsd use this file, but they're formatted differently
	read -r bsd < /var/run/dmesg.boot
	case $bsd in
	Open*)
		## openbsd cpu/mem/name
		while read -r line; do
			case $line in
				'real mem'*)
					# use the pre-formatted value which is in brackets
					mem=${line##*\(}
					mem=${mem%\)*}
				;;
				# set $cpu to everything before a comma and after the field name
				cpu0:*)
					cpu=${line#cpu0: }
					# remove excess info after the actual cpu name
					cpu=${cpu%%,*}
					# set the cpu manufacturer to the first word of the cpu
					# variable [separated by '(' or ' ']
					vendor=${cpu%%[\( ]*}
					break
				;;
				# first 2 words in the file are OpenBSD <version>
				*) [ "$ID" ] || { set -- $line; ID="$1 $2"; }
			esac
		done < /var/run/dmesg.boot
		[ -d /var/db/pkg ] && set -- /var/db/pkg/* && pkgs=$#
		read -r host < /etc/myname
		host=${host%.*}
	;;
	# everything else, assume freebsd (first line is ---<<BOOT>> or something)
	*)
		# shellcheck source=/dev/null
		. /etc/rc.conf
		# shut shellcheck up without disabling the warning
		host=${hostname:-}

		while read -r line; do
			case $line in
				# ignore useless lines at the top
				-*|'  '*) ;;
				*trademark*) ;;

				# os version
				FreeBSD*)
					# if the os is already set, no need to set it again
					[ "$ID" ] && continue
					ID=${line%%-R*}
				;;

				CPU:*)
					cpu=${cpu#CPU: }
					# remove excess info from after the actual cpu name
					cpu=${line%\(*}
				;;
				*Origin=*)
					# cpu manufacturer
					vendor=${line#*Origin=\"}
					vendor="${vendor%%\"*} "
				;;

				'real memory'*)
					# get the pre-formatted amount which is inside brackets
					mem=${line##*\(}
					mem=${mem%\)*}
					# this appears to be the final thing we need from the file,
					# no need to read it more.
					break
			esac
		done < /var/run/dmesg.boot
	;;
	esac
elif v=/System/Library/CoreServices/SystemVersion.plist; [ -f "$v" ]; then
	## macos
	# make sure this variable is empty as to not break the following loop
	temp=
	while read -r line; do
		case $line in
			# set a variable so the script knows it's on the correct line
			# (the line after this one is the important one)
			*ProductVersion*) temp=.;;
			*)
				# check if the script is reading the derired line, if not
				# don't do anything
				[ "$temp" ] || continue
				# remove everything before and including the first '>'
				ID=${line#*>}
				# remove the other side of the xml tag, and insert the actual os name
				ID="MacOS ${ID%<*}"
				# we got the info we want, end the loop.
				break
		esac
	done < "$v"
fi

eq "$0" '*fetish' && printf 'Step on me daddy\n' && exit

# help i dont know if it's a capital consistently
eq "$wm" '*[Gg][Nn][Oo][Mm][Ee]*' && wm='foot DE'

## gtk
while read -r line; do
	eq "$line" 'gtk-theme*' && gtk=${line##*=} && break
done < "${XDG_CONFIG_HOME:=$HOME/.config}/gtk-3.0/settings.ini"

# shorten $cpu and $vendor
# this is so messy due to so many inconsistencies in the model names lmao
vendor=${vendor##*Authentic}
vendor=${vendor##*Genuine}
cpu=${cpu##*) }
cpu=${cpu%% @*}
cpu=${cpu%% CPU}
cpu=${cpu##CPU }
cpu=${cpu##*AMD }
cpu=${cpu%% with*}
cpu=${cpu% *-Core*}

col() {
	printf '  '
	for i in 1 2 3 4 5 6; do
		printf '\033[9%sm▅▅' "$i"
	done
	printf '\033[0m\n'
}

print() {
	[ "$2" ] && printf '\033[9%sm%6s\033[0m%b%s\n' \
		"${accent:-4}" "$1" "${separator:- ~ }" "$2"
}

# default value
: "${info:=n user os sh wm up gtk cpu mem host kern pkgs term col n}"

for i in $info; do
	case $i in
		n) echo;;
		os) print os "$ID";;
		sh) print sh "${SHELL##*/}";;
		wm) print wm "${wm##*/}";;
		up) print up "$up";;
		gtk) print gtk "${gtk# }";;
		cpu) print cpu "$vendor$cpu";;
		mem) print mem "$mem";;
		host) print host "$model";;
		kern) print kern "$kernel";;
		pkgs) print pkgs "$pkgs";;
		term) print term "$term";;
		user) printf '%7s@%s\n' "$USER" "$host";;
		col) col;;
	esac
done
