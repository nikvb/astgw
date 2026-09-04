#!/bin/bash
set -e

echo "=== AMDY AMD Deployment ==="

# Extract original amd.py from tar
echo "Extracting amd.py from amdy.tar.gz..."
cd /var/lib/asterisk/agi-bin
tar zxvf amdy.tar.gz
chmod 755 amd.py
echo "OK: amd.py extracted"

# Create optimized amd_detect.py (the latest version from installamd.sh)
echo "Installing amd_detect.py..."
cat > /var/lib/asterisk/agi-bin/amd_detect.py << 'PYEOF'
#!/usr/bin/python3 -O

"""
Fully Optimized Asterisk AGI Answering Machine Detection (AMD) Script
Python 3.4+ Compatible Version with VID Tracking
"""

import os
import fcntl
import time
import json
import select
from websocket import create_connection
from asterisk.agi import AGI

# Configuration Constants
AUDIO_FD = 3
WS_ENDPOINT = "ws://api.amdy.io:2700"
SAMPLE_RATE = 8000
SEND_TIMES = [0.7, 1.0, 2.0, 3.0]
MAX_WAIT_TIME = 5
SELECT_TIMEOUT = 0.05
FALLBACK_CHUNK_SIZE = 8000
MACHINE_DELAY = 26
NO_DATA_SLEEP = 0.1
CONNECTION_TIMEOUT = 10
AUDIO_READ_SIZE = 9500

def log_verbose(agi, message, vid=None):
    if vid:
        agi.verbose("AMD[{}]: {}".format(vid, message))
    else:
        agi.verbose("AMD: {}".format(message))

def set_amd_variables(agi, status, cause, stats=None, vid=None):
    agi.set_variable('AMDSTATUS', status)
    agi.set_variable('AMDCAUSE', cause)
    if stats:
        agi.set_variable('AMDSTATS', stats)
    log_verbose(agi, "Variables set - Status: {}, Cause: {}".format(status, cause), vid)

def create_websocket_connection(agi, caller_name, vid=None):
    try:
        ws = create_connection(WS_ENDPOINT, timeout=CONNECTION_TIMEOUT)
        config = json.dumps({
            "config": {
                "sample_rate": SAMPLE_RATE,
                "VID": caller_name or "Unknown"
            }
        })
        ws.send(config)
        log_verbose(agi, "WebSocket connected to {}".format(WS_ENDPOINT), vid)
        return ws
    except Exception as err:
        log_verbose(agi, "WebSocket connection failed: {}".format(err), vid)
        set_amd_variables(agi, "HUMAN", "CONNECTION_ERROR", vid=vid)
        return None

def cleanup_websocket(ws):
    try:
        if ws:
            ws.send(json.dumps({"eof": 1}))
            ws.close()
    except Exception:
        pass

def setup_audio_stream():
    fcntl.fcntl(AUDIO_FD, fcntl.F_SETFL, os.O_NONBLOCK)

def process_audio_chunk(agi, ws, audio_buffer, vid=None):
    try:
        ws.send_binary(audio_buffer)
        log_verbose(agi, "Sent audio chunk: {} bytes".format(len(audio_buffer)), vid)
        response = ws.recv()
        log_verbose(agi, "AMD response: {}".format(response), vid)

        if 'HUMAN' in response:
            log_verbose(agi, "*** HUMAN DETECTED ***", vid)
            set_amd_variables(agi, "HUMAN", "HUMAN", response, vid)
            return True
        elif 'AMD' in response or 'MACHINE' in response:
            log_verbose(agi, "*** MACHINE DETECTED ***", vid)
            set_amd_variables(agi, "MACHINE", response, vid=vid)
            log_verbose(agi, "Waiting {}s for machine to complete".format(MACHINE_DELAY), vid)
            time.sleep(MACHINE_DELAY)
            return True
        return False
    except Exception as err:
        log_verbose(agi, "Audio processing error: {}".format(err), vid)
        set_amd_variables(agi, "HUMAN", "PROCESSING_ERROR", vid=vid)
        return True

def process_audio_stream(agi, ws, channel, vid=None):
    start_time = time.time()
    total_data_received = 0
    audio_buffer = b''
    send_index = 0

    log_verbose(agi, "Starting audio processing", vid)

    while True:
        current_time = time.time()
        elapsed_time = current_time - start_time

        try:
            if send_index < len(SEND_TIMES):
                time_until_next_send = SEND_TIMES[send_index] - elapsed_time
                select_timeout = max(0, min(time_until_next_send, SELECT_TIMEOUT))
            else:
                select_timeout = SELECT_TIMEOUT

            ready, _, _ = select.select([AUDIO_FD], [], [], select_timeout)

            if ready:
                try:
                    audio_chunk = os.read(AUDIO_FD, AUDIO_READ_SIZE)
                    if audio_chunk:
                        audio_buffer += audio_chunk
                    else:
                        log_verbose(agi, "End of audio stream", vid)
                        set_amd_variables(agi, "HANGUP", "NO_AUDIO", vid=vid)
                        return
                except OSError as err:
                    if err.errno == 11:
                        continue
                    else:
                        raise

            if elapsed_time > MAX_WAIT_TIME:
                log_verbose(agi, "Timeout after {}s".format(MAX_WAIT_TIME), vid)
                if total_data_received < 1:
                    set_amd_variables(agi, 'NOTSURE', 'NO_AUDIO_TIMEOUT', vid=vid)
                else:
                    set_amd_variables(agi, "HANGUP", "AUDIO_TIMEOUT", vid=vid)
                return

            if send_index < len(SEND_TIMES) and elapsed_time >= SEND_TIMES[send_index]:
                if len(audio_buffer) > 0:
                    total_data_received += len(audio_buffer)
                    if process_audio_chunk(agi, ws, audio_buffer, vid):
                        return
                    audio_buffer = b''
                send_index += 1

            elif send_index >= len(SEND_TIMES) and len(audio_buffer) >= FALLBACK_CHUNK_SIZE:
                total_data_received += len(audio_buffer)
                if process_audio_chunk(agi, ws, audio_buffer, vid):
                    return
                audio_buffer = b''

        except Exception as err:
            log_verbose(agi, "Error: {}".format(err), vid)
            set_amd_variables(agi, "HUMAN", "PROCESSING_ERROR", vid=vid)
            return

def start_agi():
    agi = AGI()
    ws = None

    try:
        caller_id = agi.env.get('agi_callerid', 'Unknown')
        caller_name = agi.env.get('agi_calleridname', 'Unknown')
        extension = agi.env.get('agi_extension', 'Unknown')
        channel = agi.env.get('agi_channel', 'Unknown')

        vid = caller_name

        log_verbose(agi, "AMD DETECTION STARTED - Caller: {} ({}) Ext: {}".format(caller_id, caller_name, extension), vid)

        ws = create_websocket_connection(agi, caller_name, vid)
        if not ws:
            return

        setup_audio_stream()
        process_audio_stream(agi, ws, channel, vid)

        log_verbose(agi, "AMD DETECTION COMPLETE", vid)

    except Exception as err:
        log_verbose(agi, "FATAL ERROR: {}".format(err), vid if 'vid' in locals() else None)
        set_amd_variables(agi, "HUMAN", "FATAL_ERROR", vid=vid if 'vid' in locals() else None)

    finally:
        cleanup_websocket(ws)

if __name__ == "__main__":
    start_agi()
PYEOF

chmod 755 /var/lib/asterisk/agi-bin/amd_detect.py
echo "OK: amd_detect.py installed"

# Create amd.sh wrapper
echo "Installing amd.sh wrapper..."
cat > /var/lib/asterisk/agi-bin/amd.sh << 'SHEOF'
#!/bin/bash
# AMD Wrapper Script - sets optimal Python environment
export PYTHONOPTIMIZE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1
exec nice -n 10 /usr/bin/python3 -O -B /var/lib/asterisk/agi-bin/amd_detect.py
SHEOF

chmod 755 /var/lib/asterisk/agi-bin/amd.sh
echo "OK: amd.sh wrapper installed"

# Pre-compile Python scripts
echo "Pre-compiling Python scripts..."
python3 -m py_compile /var/lib/asterisk/agi-bin/amd_detect.py && echo "OK: amd_detect.py compiled"
python3 -m py_compile /var/lib/asterisk/agi-bin/amd.py && echo "OK: amd.py compiled"

# Also create optimized bytecode
python3 -O -m py_compile /var/lib/asterisk/agi-bin/amd_detect.py && echo "OK: amd_detect.py optimized bytecode"
python3 -O -m py_compile /var/lib/asterisk/agi-bin/amd.py && echo "OK: amd.py optimized bytecode"

# Compile entire agi-bin directory
python3 -m compileall /var/lib/asterisk/agi-bin/ 2>&1 | grep -E "Compiling|OK" || true
python3 -O -m compileall /var/lib/asterisk/agi-bin/ 2>&1 | grep -E "Compiling|OK" || true

echo ""
echo "=== Files deployed ==="
ls -la /var/lib/asterisk/agi-bin/amd*
echo ""
echo "=== Compiled bytecode ==="
find /var/lib/asterisk/agi-bin/__pycache__/ -name "amd*" -ls 2>/dev/null || echo "No __pycache__ found"
echo ""

# Verify imports work
echo "=== Testing imports ==="
python3 -c "from asterisk.agi import AGI; print('pyst2 OK')"
python3 -c "from websocket import create_connection; print('websocket OK')"
python3 -c "import json, os, fcntl, time, select; print('stdlib OK')"

echo ""
echo "=== AMDY AMD Deployment Complete ==="
