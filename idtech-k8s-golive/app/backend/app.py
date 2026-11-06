import os
import time
import socket

import redis
from flask import Flask, jsonify

app = Flask(__name__)

VERSION = os.getenv("APP_VERSION", "1.0")
POD_NAME = os.getenv("POD_NAME", socket.gethostname())

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis-headless.idtech-backend.svc.cluster.local"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.environ.get("REDIS_PASSWORD"),
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
)


@app.get("/health")
def health():
    return jsonify(
        status="ok",
        version=VERSION,
        release="rolling-update-demo",
    )


@app.get("/api/visits")
def visits():
    try:
        count = redis_client.incr("visits")
        return jsonify(
            visits=count,
            pod=POD_NAME,
            version=VERSION,
        )
    except redis.RedisError:
        return jsonify(error="Redis unavailable"), 503


@app.get("/api/load")
def load():
    duration = min(
        max(float(os.getenv("LOAD_DURATION", "3")), 0),
        10,
    )

    end = time.monotonic() + duration
    counter = 0

    while time.monotonic() < end:
        counter += 1

    return jsonify(
        status="completed",
        pod=POD_NAME,
        version=VERSION,
        iterations=counter,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)