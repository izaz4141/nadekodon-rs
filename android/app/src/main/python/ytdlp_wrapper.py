import json
import yt_dlp

def run_ytdlp(url):
    ydl_opts = {
        'dump_single_json': True,
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
    }
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            sanitized = ydl.sanitize_info(info)
            return json.dumps(sanitized)
    except Exception as e:
        return json.dumps({'error': str(e)})

def get_version():
    try:
        return json.dumps({'version': yt_dlp.version.__version__})
    except Exception as e:
        return json.dumps({'error': str(e)})

