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

def download_video(url, options_json, callback):
    try:
        options = json.loads(options_json)
        
        def progress_hook(d):
            if d['status'] == 'downloading':
                progress = {
                    'status': 'downloading',
                    'downloaded_bytes': d.get('downloaded_bytes', 0),
                    'total_bytes': d.get('total_bytes') or d.get('total_bytes_estimate', 0),
                    'speed': d.get('speed', 0),
                }
                callback.onProgress(json.dumps(progress))
            elif d['status'] == 'finished':
                progress = {
                    'status': 'finished',
                    'filename': d.get('filename', ''),
                    'total_bytes': d.get('total_bytes', 0),
                }
                callback.onProgress(json.dumps(progress))

        ydl_opts = {
            'progress_hooks': [progress_hook],
            'outtmpl': options.get('outtmpl', '%(title)s.%(ext)s'),
            'format': options.get('format', 'best'),
            'noplaylist': True,
            'quiet': True,
            'no_warnings': True,
        }

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])
            
        return json.dumps({'status': 'success'})

    except Exception as e:
        return json.dumps({'status': 'error', 'error': str(e)})
