#!/bin/zsh
# Device-pass log capture (#133, #58/#179, #61 and anything else that surfaces).
#
# Captures EVERYTHING to a timestamped file and greps afterwards, rather than
# filtering live. Live filtering was tempting and wrong: if the filter is even
# slightly off the evidence is gone, and the check has to be re-run on a device
# whose state has already moved on.
#
# Usage:  ./scripts/device-pass-capture.sh start     # begin capture
#         ./scripts/device-pass-capture.sh mark A1   # timestamp a check boundary
#         ./scripts/device-pass-capture.sh stop
#         ./scripts/device-pass-capture.sh grep133

set -u
LOG=/tmp/t27-device-pass.log
PIDF=/tmp/t27-capture.pid

case "${1:-}" in
  start)
    if [[ -f $PIDF ]] && kill -0 "$(cat $PIDF)" 2>/dev/null; then
      echo "already capturing (pid $(cat $PIDF)) -> $LOG"; exit 0
    fi
    if ! idevice_id -l | grep -q .; then
      echo "NO DEVICE. Cable the phone to this Mac and tap Trust, then retry." >&2
      exit 1
    fi
    : > $LOG
    nohup idevicesyslog >> $LOG 2>&1 &
    echo $! > $PIDF
    disown
    sleep 2
    echo "capturing -> $LOG (pid $(cat $PIDF))"
    ;;

  mark)
    echo "########## MARK ${2:-?} $(date '+%H:%M:%S') ##########" >> $LOG
    echo "marked ${2:-?}"
    ;;

  stop)
    [[ -f $PIDF ]] && kill "$(cat $PIDF)" 2>/dev/null && rm -f $PIDF
    echo "stopped. $(wc -l < $LOG) lines in $LOG"
    ;;

  # ---- per-check recipes -------------------------------------------------

  # A12 / #133: push registration idempotency.
  # PASS = at most one line per profile per launch.
  # "registration deferred" is NOT a failure - it is the honest no-token path (#146).
  grep133)
    grep -nE "registerPushToken:" $LOG
    echo "--- counts ---"
    printf "accepted:  %s\n" "$(grep -c 'accepted push registration' $LOG)"
    printf "deferred:  %s\n" "$(grep -c 'registration deferred' $LOG)"
    printf "failed:    %s\n" "$(grep -c 'push/register failed' $LOG)"
    ;;

  # A1 / #58 + #179: control taps.
  # Cold-swallow signature = "Successfully ran" with NO PerformAction and no perform() between.
  grep58)
    grep -nE "chronod|AppIntents|OpenHermesChatIntent|OpenHermesVoiceIntent|Prepared url" $LOG
    ;;

  # B1 / #61: which guard tripped on a degenerate card.
  # Should now be able to name the exact-prefix branch.
  grep61)
    grep -nE "conversationCard:|degenerate" $LOG
    ;;

  # Crashes / faults anywhere in the pass.
  grepfault)
    grep -nE "Fatal|fatal error|Crash|crash report|SIGABRT|EXC_BAD" $LOG
    ;;

  *)
    echo "usage: $0 {start|mark <id>|stop|grep133|grep58|grep61|grepfault}"
    exit 1
    ;;
esac
