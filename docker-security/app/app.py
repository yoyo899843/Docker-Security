import socket
import subprocess

from flask import Flask, render_template, request

app = Flask(__name__)


@app.route("/", methods=["GET", "POST"])
def index():
    host = ""
    output = ""
    if request.method == "POST":
        host = request.form.get("host", "")
        cmd = "ping -c 2 " + host
        try:
            output = subprocess.check_output(
                cmd, shell=True, stderr=subprocess.STDOUT, timeout=15
            ).decode("utf-8", "replace")
        except subprocess.CalledProcessError as e:
            output = e.output.decode("utf-8", "replace")
        except subprocess.TimeoutExpired:
            output = "(指令逾時)"

    return render_template(
        "index.html",
        host=host,
        output=output,
        hostname=socket.gethostname(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
