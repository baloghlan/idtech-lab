from flask import Flask
from datetime import datetime
import os
import redis

app = Flask(__name__)
redis_client = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=6379)

@app.route('/')
def home():
    return 'IDTECH Learning Portal is running'

@app.route('/health')
def health():
    return {'status': 'healthy'}

@app.route('/visits')
def visits():
    count = redis_client.incr('visits')
    return {'visits': count, 'time': datetime.now().isoformat()}

app.run(host='0.0.0.0', port=5000)
