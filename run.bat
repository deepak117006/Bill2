@echo off
if not exist .venv (py -m venv .venv && .venv\Scripts\pip install -q -r requirements.txt)
start "" http://127.0.0.1:5000
.venv\Scripts\python app.py
