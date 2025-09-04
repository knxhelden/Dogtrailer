from flask import Flask, Response, render_template
from picamera2 import Picamera2
import logging
import io
import time
import libcamera
import atexit
import board
import adafruit_dht
import RPi.GPIO as GPIO

app = Flask(__name__)

###### GLOBAL CONFIGURATION ######
relais1Pin = 23
relais2Pin = 24
tempPin = "D4"
##################################

# GPIO Konfiguration
try:
    GPIO.setup(relais1Pin, GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(relais2Pin, GPIO.OUT, initial=GPIO.HIGH)
except Exception as ex:
    app.logger.error(f"GPIO setup failed: {ex}", exc_info=True)
    GPIO.cleanup()
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(relais1Pin, GPIO.OUT, initial=GPIO.HIGH)
    GPIO.setup(relais2Pin, GPIO.OUT, initial=GPIO.HIGH)

# AM2302 Konfiguration
dhtboard = getattr(board, tempPin)
dhtDevice = adafruit_dht.DHT22(dhtboard, use_pulseio=False)

# Kamera Konfiguration
camera = None

def initialize_camera():
    global camera
    if camera is None:
        camera = Picamera2()
        camera_config = camera.create_video_configuration(main={"size": (1024, 768)})
        camera_config["transform"] = libcamera.Transform(hflip=1, vflip=1)
        camera.configure(camera_config)
        camera.start()

def cleanup():
    global camera
    global dhtDevice
    if camera:
        camera.stop()
        camera.close()
        camera = None

    if dhtDevice:
        dhtDevice.exit()

def generate_frames():
    global camera
    while True:
        with io.BytesIO() as stream:
            camera.capture_file(stream, format='jpeg')
            stream.seek(0)
            frame = stream.read()
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

def read_sensor():
    global dhtDevice

    templateData = None

    while (templateData == None):
        try:
            templateData = {
                'temperature': dhtDevice.temperature,
                'humidity': dhtDevice.humidity,
                'stateRelais1': GPIO.input(relais1Pin),
                'stateRelais2': GPIO.input(relais2Pin)
            }
        except RuntimeError as error:
            time.sleep(2.0)
    return templateData

@app.route('/')
def index():
    templateData = read_sensor()

    return render_template("index.html", **templateData)

@app.route("/<boxName>/<action>")
def action(boxName, action):
    if boxName == "lightleft":
        box = relais1Pin
    if boxName == "lightright":
        box = relais2Pin

    if action == "on":
        GPIO.output(box, GPIO.LOW)
    if action == "off":
        GPIO.output(box, GPIO.HIGH)

    return ""

@app.route('/config')
def config():
    return render_template("config.html")

@app.route('/help')
def help():
    return render_template("help.html")

@app.route('/video_feed')
def video_feed():
    initialize_camera()
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

# Register the cleanup function to be called on exit
atexit.register(cleanup)

if __name__ == '__main__':
    try:
        # Flask Logger configuration
        app.logger.setLevel(logging.DEBUG)

        app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)
    except KeyboardInterrupt:
        # Clean up when the script is interrupted (e.g., Ctrl+C)
        cleanup()
