#!/usr/bin/env bash

# Enforce mcs user, but allow access by admins
MCS_USER="mcs"
if [ "$USER" != "$MCS_USER" ]; then
	sudo -u "$MCS_USER" -s "/usr/bin/bash" "$0" "$@"
	exit $?
fi


# Mutable config
MIN_RAM="1024"
MAX_RAM="1024"
TIMEOUT="10"
SERVER_ROOT="$HOME"
# /Mutable config

# Read config file before setting any non-mutual variables
# MCS_USER is an exception, since it is not used later
source "/etc/mcsctl.conf" &> /dev/null

# Immutable config
SERVER_ID="$2"
SERVER_NAME="mcserver$SERVER_ID"
SERVER_DIR="$SERVER_ROOT/$SERVER_NAME"
SERVER_APP="$SERVER_DIR/server.jar"
# /Immutable config

# Commands
CMD_HELP="help"
CMD_STATUS="status"
CMD_START="start"
CMD_STOP="stop"
CMD_RESTART="restart"
CMD_CREATE="create"
CMD_UPDATE="update"
CMD_DESTROY="destroy"
# /Commands

# Results
SUCCESS="0"
ERROR_UNKNOWN_COMMAND="1"
ERROR_ID_MISSING="2"
ERROR_SERVER_MISSING="3"
ERROR_SERVER_APP_MISSING="4"
ERROR_SCRAPE_FAILED="5"
ERROR_DOWNLOAD_FAILED="6"
ERROR_SERVER_ACTIVE="7"
ERROR_EULA_FILE_MISSING="8"
ERROR_PROPERTIES_FILE_MISSING="9"
# /Results


custom_date() {
	echo "$(date +"%Y")_$(date +"%m")_$(date +"%d")-$(date +"%H")_$(date +"%M")_$(date +"%S")"
}

screen_active() {
	if [ -n "$(screen -list | grep -o "$SERVER_NAME")" ]; then
		return $(true)
	else
		return $(false)
	fi
}

wait_screen_start() {
	while ! screen_active; do
		sleep 0.1
	done
}

wait_screen_stop() {
	while screen_active; do
		sleep 0.1
	done
}

server_active() {
	local PROCESSES="$(ps -h)"
	if [ -n "$(echo "$PROCESSES" | grep -o "$SERVER_APP")" ]; then
		return $(true)
	else
		return $(false)
	fi
}

wait_server_start() {
	while ! server_active; do
		sleep 0.1
	done
}

wait_server_stop() {
	while server_active; do
		sleep 0.1
	done
}

status() {
	if screen_active; then
		echo -n "Screen active, "
	else
		echo -n "Screen inactive, "
	fi

	if server_active; then
		echo "Server active"
	else
		echo "Server inactive"
	fi
}

start() {
	echo -n $(custom_date) "Starting server... "

	if [ ! -e "$SERVER_APP" ]; then
		echo "SERVER_APP does not exist -> aborted"
		exit $ERROR_SERVER_APP_MISSING
	fi

	# start screen session
	if ! screen_active; then
		screen -dmS "$SERVER_NAME"
		wait_screen_start
	fi

	# start server application in working directory
	if ! server_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "cd \"$SERVER_DIR\"; java -Xms${MIN_RAM}M -Xmx${MAX_RAM}M -jar \"$SERVER_APP\" nogui\n"
		wait_server_start
	fi

	echo "done"
}

stop() {
	echo -n $(custom_date) "Stopping server... "

	# stop server application with timeout
	if server_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "say ATTENTION! Server will be shut down in $TIMEOUT seconds!\n"
		sleep "$TIMEOUT"
		screen -S "$SERVER_NAME" -p 0 -X stuff "stop\n"
		wait_server_stop
	fi

	# stop screen session
	if screen_active; then
		screen -S "$SERVER_NAME" -p 0 -X stuff "exit\n"
		wait_screen_stop
	fi

	echo "done"
}

download() {
	echo -n $(custom_date) "Downloading latest version... "

	if server_active; then
		echo "server active -> aborted"
		exit $ERROR_SERVER_ACTIVE
	fi

	# In preparation for issue #16
	#local LATEST_VERSION=$(curl -s -L "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r ".latest.release")
	
	local METADATA_URL=$(curl -s -L "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r ".versions[0].url")
	local SERVER_URL=$(curl -s -L "$METADATA_URL" | jq -r ".downloads.server.url")

	if [ -z "$SERVER_URL" ]; then
		echo "failed to scrape url -> aborted"
		exit $ERROR_SCRAPE_FAILED
	fi

	mkdir -p "$SERVER_DIR"
	if ! $(curl -s -L -o "$SERVER_APP" "$SERVER_URL"); then
		echo "failed to download jar -> aborted"
		exit $ERROR_DOWNLOAD_FAILED
	fi

	echo "done"
}

configure() {
	echo -n $(custom_date) "Configuring server... "

	# EULA
	echo "eula=TRUE" > "$SERVER_DIR/eula.txt"

	# Properties
	echo "server-port=$((25564 + $SERVER_ID))
	motd=Welcome to MC-Server #$SERVER_ID.
	player-idle-timeout=5
	snooper-enabled=false
	view-distance=15" > "$SERVER_DIR/server.properties"

	echo "done"
}

remove() {
	echo -n $(custom_date) "Removing server... "

	if server_active; then
		echo "server active -> aborted"
		exit $ERROR_SERVER_ACTIVE
	fi

	rm -rf "$SERVER_DIR"

	echo "done"
}

help() {
	local MY_NAME="${0##*/}"
	echo "Usage: $MY_NAME {$CMD_HELP|$CMD_STATUS|$CMD_START|$CMD_STOP|$CMD_RESTART|$CMD_CREATE|$CMD_UPDATE|$CMD_DESTROY}
		$CMD_HELP		Prints this help.
		$CMD_STATUS	<id>	Status of a server and its screen session.
		$CMD_START	<id>	Starts a server inside a screen session.
		$CMD_STOP	<id>	Stops a server and its screen session.
		$CMD_RESTART	<id>	Restarts a server.
		$CMD_CREATE	<id>	Creates a server in \"$SERVER_DIR\".
		$CMD_UPDATE	<id>	Downloads a new minecraft server executable for the specified server.
		$CMD_DESTROY	<id>	Removes all files of a server."
}

require_server_id() {
	if [ -z "$SERVER_ID" ]; then
		echo $(custom_date) "Missing server id!"
		exit $ERROR_ID_MISSING
	fi
}

require_server_exists() {
	require_server_id
	
	if [ ! -d "$SERVER_DIR" ]; then
		echo $(custom_date) "Server does not exist!"
		exit $ERROR_SERVER_MISSING
	fi
}


case "$1" in
	"$CMD_HELP")
		help
		;;
	"$CMD_STATUS")
		require_server_exists
		status
		;;
	"$CMD_START")
		require_server_exists
		start
		;;
	"$CMD_STOP")
		require_server_id
		stop
		;;
	"$CMD_RESTART")
		require_server_exists
		stop
		start
		;;
	"$CMD_CREATE")
		require_server_id
		download
		configure
		;;
	"$CMD_UPDATE")
		require_server_exists
		download
		;;
	"$CMD_DESTROY")
		require_server_id
		read -p "Delete world data and configuration of server #$SERVER_ID? [y/n]" -n 1 -r; echo ""
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			remove
		fi
		;;
	*)
		help
		exit $ERROR_UNKNOWN_COMMAND
		;;
esac

exit $SUCCESS
