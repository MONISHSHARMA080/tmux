#!/bin/bash
# Default values
SESSION_NAME="dev"
COMMANDS=()
DIRECTORIES=()
CURRENT_DIR="$(pwd)"
echo "new version"

# Help function
function show_help {
  echo "Usage: $0 [-n SESSION_NAME] [-c COMMAND] [-d DIRECTORY] [-c COMMAND] [-d DIRECTORY] ..."
  echo "Creates or attaches to a tmux session with the given name and executes commands in separate windows/tabs."
  echo ""
  echo "Options:"
  echo " -n SESSION_NAME Name of the tmux session (default: dev)"
  echo " -c COMMAND Command to run in a separate window (can be specified multiple times)"
  echo " -d DIRECTORY Directory to run the following commands in until another -d is specified"
  echo " Can be a relative path or subdirectory name"
  echo " -h Show this help message"
  echo ""
  echo "Tips:"
  echo " - Use Ctrl+b n to move to next window, Ctrl+b p for previous window"
  echo " - Use Ctrl+b d to detach (session will stay alive in background)"
  echo " - Use Ctrl+b q to quit and detach (session will stay alive in background)"
  echo " - To kill session completely, use 'tmux kill-session -t SESSION_NAME'"
  exit 0
}

# Parse command line arguments
current_dir="$CURRENT_DIR" # Start with current directory as default
last_flag=""               # Track the last flag to determine directory context

# Process arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  -n)
    SESSION_NAME="$2"
    last_flag="-n"
    shift 2
    ;;
  -c)
    COMMANDS+=("$2")
    if [[ "$last_flag" == "-d" ]]; then
      # If previous flag was -d, use the current_dir
      DIRECTORIES+=("$current_dir")
    else
      # Otherwise reset to the original CURRENT_DIR
      DIRECTORIES+=("$CURRENT_DIR")
    fi
    last_flag="-c"
    shift 2
    ;;
  -d)
    dir="$2"
    # If it's not an absolute path, make it relative to current directory
    if [[ ! "$dir" == /* ]]; then
      # Check if it's a subdirectory of the *original* CURRENT_DIR first
      if [[ -d "$CURRENT_DIR/$dir" ]]; then
        dir="$CURRENT_DIR/$dir"
      # Then check if it's a valid path relative to the *current script execution dir*
      elif [[ -d "$dir" ]]; then
        dir="$(cd "$dir" && pwd)" # Resolve to absolute path
      else
        echo "Directory '$dir' not found relative to '$CURRENT_DIR' or as a direct path."
        exit 1
      fi
    elif [[ ! -d "$dir" ]]; then
      echo "Absolute directory path '$dir' not found."
      exit 1
    fi
    # Set the current directory for future commands
    current_dir="$dir"
    last_flag="-d"
    shift 2
    ;;
  -h)
    show_help
    shift
    ;;
  *)
    echo "Unknown option: $1"
    show_help
    ;;
  esac
done

# If no commands were provided, show help
if [ ${#COMMANDS[@]} -eq 0 ]; then
  echo "No commands specified."
  show_help
fi

# Debug output to verify directories and commands
echo "--- Debug: Commands and Directories Parsed ---"
for ((i = 0; i < ${#COMMANDS[@]}; i++)); do
  echo "Index $i: Command='${COMMANDS[$i]}' in Directory='${DIRECTORIES[$i]}'"
done
echo "---------------------------------------------"

# Check if session exists
tmux has-session -t "$SESSION_NAME" 2>/dev/null
# $? is the exit status of the last command
if [ $? -eq 0 ]; then
  echo "Session $SESSION_NAME already exists. Attaching..."
  tmux attach-session -t "$SESSION_NAME"
  exit 0
fi

# Session doesn't exist, create it
echo "Creating new session $SESSION_NAME..."
# Create the session with the first command's directory
# Use unique but simple initial window name, rename later
initial_window_name="init-win-0-${RANDOM}" # Add random suffix just in case
tmux new-session -d -s "$SESSION_NAME" -c "${DIRECTORIES[0]}" -n "$initial_window_name"

# *** ADDED DELAY ***
sleep 0.5 # Adjust if needed

# Check if session was actually created before proceeding
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Error: Failed to create tmux session '$SESSION_NAME'."
  exit 1
fi

# Set custom key binding for easy detach using Ctrl+b q
tmux bind-key -T "$SESSION_NAME" q detach

# --- Process First Window (Index 0) ---
first_window_target="$SESSION_NAME:$initial_window_name" # Target by initial name
first_window_final_name="cmd-1: ${COMMANDS[0]:0:50}"     # Calculate final name
echo "Renaming window 0 to '$first_window_final_name'"
tmux rename-window -t "$first_window_target" "$first_window_final_name"

# Add pwd for verification; command only (no cd needed)
echo "Sending to window 0 ('$first_window_final_name'): pwd && ${COMMANDS[0]}"
# Target using the NEW name for send-keys, rename should be fast enough after sleep
tmux send-keys -t "$SESSION_NAME:$first_window_final_name" " ${COMMANDS[0]}" C-m

# --- Create and Process Additional Windows (Index 1 onwards) ---
for ((i = 1; i < ${#COMMANDS[@]}; i++)); do
  window_name="cmd-$((i + 1)): ${COMMANDS[$i]:0:50}" # Truncate long commands
  echo "Creating window $i: Name='$window_name', Dir='${DIRECTORIES[$i]}'"
  # Create new window starting in the correct directory using -c
  tmux new-window -t "$SESSION_NAME" -n "$window_name" -c "${DIRECTORIES[$i]}"

  # *** ADDED SMALL DELAY FOR WINDOW CREATION ***
  sleep 0.1 # Small delay allows window shell to potentially finish cd

  # Target the window by its name to send keys
  # Add pwd for verification
  echo "Sending to window $i ('$window_name'): pwd && ${COMMANDS[$i]}"
  tmux send-keys -t "$SESSION_NAME:$window_name" " ${COMMANDS[$i]}" C-m
done

# --- Final Steps ---
# Start with the first command window selected (target by final name)
echo "Selecting first command window: '$first_window_final_name'"
tmux select-window -t "$SESSION_NAME:$first_window_final_name"

# Display a notification about how to detach
echo -e "\n----- TMUX SESSION HELP -----"
echo -e "• To switch windows: Ctrl+b n (next), Ctrl+b p (previous)"
echo -e "• To detach (preserve session): Ctrl+b d OR Ctrl+b q"
echo -e "• To reattach later: tmux attach -t $SESSION_NAME"
echo -e "• To kill session: tmux kill-session -t $SESSION_NAME"
echo -e "---------------------------\n"

# Attach to the session
echo "Attaching to session $SESSION_NAME..."
tmux attach-session -t "$SESSION_NAME"
