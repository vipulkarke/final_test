from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def home():
    return "Welcome to vipulkarke Final Test API Server"

@app.route("/api/health")
def health():
    return jsonify({"status": "healthy"}), 200

@app.route("/api/greet/<name>")
def greet(name):
    return jsonify({"message": f"Hello, {name}! Welcome to the API."}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
