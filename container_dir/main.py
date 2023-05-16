from flask import Flask, render_template
import requests
import json
import os

app = Flask(__name__)

def get_meme():
    url = "https://meme-api.com/gimme"
    response = json.loads(requests.request(method='GET', url = url).text)
    meme_large = response["preview"][-2]
    subreddit = response["subreddit"]
    return meme_large, subreddit

@app.route('/')
def hello():
    meme_pic, subreddit = get_meme()
    return render_template('index.html', meme_pic=meme_pic, subreddit=subreddit)

if __name__ == "__main__":
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)