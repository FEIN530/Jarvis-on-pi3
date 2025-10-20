#!/bin/bash
# install_full_jarvis.sh
# One-shot installer for offline Jarvis on Raspberry Pi 3

set -e
USER_HOME="/home/pi"     # Change if your username isn't 'pi'
JARVIS_DIR="$USER_HOME/jarvis"
MUSIC_DIR="$USER_HOME/Music"
LOG_FILE="/var/log/jarvis.log"

echo "=== Updating system packages ==="
apt update && apt upgrade -y

echo "=== Installing dependencies ==="
apt install -y python3-pip portaudio19-dev mpg123 git unzip wget curl -y
pip3 install --upgrade pip
pip3 install pvporcupine vosk sounddevice piper-tts numpy pyaudio

echo "=== Creating directories ==="
mkdir -p "$JARVIS_DIR/models" "$MUSIC_DIR"

echo "=== Downloading offline models ==="
cd "$JARVIS_DIR/models"

# Vosk STT model
if [ ! -d "vosk-model-small-en-us-0.15" ]; then
  wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
  unzip vosk-model-small-en-us-0.15.zip
  rm vosk-model-small-en-us-0.15.zip
fi

# Piper TTS model
if [ ! -f "en_US-libritts_r-medium.onnx" ]; then
  wget https://github.com/rhasspy/piper/releases/download/v0.0.2/en_US-libritts_r-medium.onnx
  wget https://github.com/rhasspy/piper/releases/download/v0.0.2/en_US-libritts_r-medium.onnx.json
fi

echo "=== Writing Jarvis Python script ==="
cat > "$JARVIS_DIR/jarvis_local_music.py" <<'EOF'
#!/usr/bin/env python3
import os, time, json, random, subprocess
import numpy as np
import pvporcupine, pyaudio, sounddevice as sd
from vosk import Model, KaldiRecognizer
from piper import PiperVoice

BASE_DIR = os.path.expanduser('~/jarvis')
MUSIC_DIR = os.path.expanduser('~/Music')
WAKE_PATH = os.path.join(BASE_DIR, 'models', 'hey-jarvis.ppn')
VOSK_PATH = os.path.join(BASE_DIR, 'models', 'vosk-model-small-en-us-0.15')
VOICE_PATH = os.path.join(BASE_DIR, 'models', 'en_US-libritts_r-medium.onnx')

print("[Jarvis] Booting systems...")
voice = PiperVoice.load(VOICE_PATH)
vosk_model = Model(VOSK_PATH)
recognizer = KaldiRecognizer(vosk_model, 16000)
porcupine = pvporcupine.create(keyword_paths=[WAKE_PATH])
pa = pyaudio.PyAudio()
stream = pa.open(format=pyaudio.paInt16, channels=1, rate=porcupine.sample_rate,
                 input=True, frames_per_buffer=512)

def speak(text):
    print("[Jarvis]:", text)
    voice.speak(text)

def listen_for_command(seconds=5):
    print("[Jarvis] Listening...")
    audio = sd.rec(int(seconds * 16000), samplerate=16000, channels=1, dtype='int16')
    sd.wait()
    recognizer.AcceptWaveform(audio.tobytes())
    result = json.loads(recognizer.Result())
    return result.get("text", "").lower()

def play_song(name=None):
    files = [f for f in os.listdir(MUSIC_DIR) if f.lower().endswith(('.mp3', '.wav', '.ogg'))]
    if not files:
        speak("I couldn't find any music files in your music folder, sir.")
        return
    if name:
        for f in files:
            if name in f.lower():
                song = os.path.join(MUSIC_DIR, f)
                speak(f"Playing {f}")
                subprocess.Popen(['mpg123', '-q', song])
                return
        speak("I couldn't find that song, sir.")
    else:
        song = os.path.join(MUSIC_DIR, random.choice(files))
        speak(f"Playing {os.path.basename(song)}")
        subprocess.Popen(['mpg123', '-q', song])

def stop_music():
    subprocess.run(['pkill', 'mpg123'])
    speak("Music stopped.")

def next_song():
    stop_music()
    play_song()

def process_command(cmd):
    if not cmd: return
    print("[Command]:", cmd)
    if "play music" in cmd:
        play_song()
    elif cmd.startswith("play "):
        name = cmd.replace("play ", "").strip()
        play_song(name)
    elif "stop music" in cmd or "pause" in cmd:
        stop_music()
    elif "next" in cmd:
        next_song()
    elif "time" in cmd:
        speak(f"The time is {time.strftime('%I:%M %p')}.")
    elif "date" in cmd:
        speak(f"Today is {time.strftime('%A, %B %d, %Y')}.")
    elif "shutdown" in cmd:
        speak("Shutting down. Goodbye, sir.")
        subprocess.run(["sudo", "shutdown", "now"])
    elif "goodbye" in cmd or "exit" in cmd:
        speak("Goodbye, sir.")
        exit()
    else:
        speak("I'm not sure what you mean, sir.")

# Dynamic greeting
hour = int(time.strftime("%H"))
if hour < 12:
    greeting = "Good morning"
elif hour < 18:
    greeting = "Good afternoon"
else:
    greeting = "Good evening"

speak(f"Systems online. {greeting}, sir. Jarvis boot sequence complete.")
print("[Jarvis] Awaiting wake word...")

try:
    while True:
        pcm = stream.read(512, exception_on_overflow=False)
        pcm = np.frombuffer(pcm, dtype=np.int16)
        result = porcupine.process(pcm)
        if result >= 0:
            speak("Yes, sir?")
            cmd = listen_for_command()
            process_command(cmd)
            print("[Jarvis] Listening for next wake word...")
except KeyboardInterrupt:
    print("Exiting...")
finally:
    stream.stop_stream()
    stream.close()
    pa.terminate()
    porcupine.delete()
EOF

chmod +x "$JARVIS_DIR/jarvis_local_music.py"

echo "=== Creating systemd service for auto-start ==="
SERVICE_FILE="/etc/systemd/system/jarvis.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Jarvis Voice Assistant
After=network.target sound.target

[Service]
ExecStart=/usr/bin/python3 $JARVIS_DIR/jarvis_local_music.py
WorkingDirectory=$JARVIS_DIR
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
Restart=always
RestartSec=5
User=pi
Environment=PYTHONUNBUFFERED=1
ExecStartPre=/bin/sleep 10

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable jarvis.service

echo "=== Installation Complete ==="
echo "Place your 'hey-jarvis.ppn' wake word file in $JARVIS_DIR/models/"
echo "Add music files (.mp3, .wav, .ogg) to $MUSIC_DIR/"
echo "Jarvis will automatically start on boot."
echo "You can manually start with: sudo systemctl start jarvis"
echo "To check status: systemctl status jarvis"
echo "Logs: tail -f /var/log/jarvis.log"
echo "=== Reboot recommended ==="
