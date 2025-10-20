#!/usr/bin/env python3
import os, time, json, random, subprocess
import numpy as np
import sounddevice as sd
from vosk import Model, KaldiRecognizer
from piper import PiperVoice

# === CONFIG ===
BASE_DIR = os.path.expanduser('~/jarvis')
MUSIC_DIR = os.path.expanduser('~/Music')
VOSK_PATH = os.path.join(BASE_DIR, 'models', 'vosk-model-small-en-us-0.15')
VOICE_PATH = os.path.join(BASE_DIR, 'models', 'en_US-libritts_r-medium.onnx')

# === INIT SYSTEMS ===
print("[Jarvis] Booting systems...")
voice = PiperVoice.load(VOICE_PATH)
vosk_model = Model(VOSK_PATH)
recognizer = KaldiRecognizer(vosk_model, 16000)

# === FUNCTIONS ===
def speak(text):
    print("[Jarvis]:", text)
    voice.speak(text)

def listen_burst(duration=3):
    """Record a short burst of audio and return recognized text"""
    audio = sd.rec(int(duration * 16000), samplerate=16000, channels=1, dtype='int16')
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

# === STARTUP GREETING ===
hour = int(time.strftime("%H"))
if hour < 12:
    greeting = "Good morning"
elif hour < 18:
    greeting = "Good afternoon"
else:
    greeting = "Good evening"

speak(f"Systems online. {greeting}, sir. Jarvis boot sequence complete.")
print("[Jarvis] Awaiting commands (say 'Jarvis' to trigger)...")

# === MAIN LOOP (burst mode) ===
try:
    while True:
        cmd = listen_burst(duration=3)
        if "jarvis" in cmd:
            speak("Yes, sir?")
            # Remove the trigger word "jarvis" before processing
            cmd = cmd.replace("jarvis", "").strip()
            process_command(cmd)
        # Short sleep to reduce CPU load
        time.sleep(0.5)
except KeyboardInterrupt:
    print("Exiting...")
