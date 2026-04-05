{{flutter_js}}
{{flutter_build_config}}

const loadingSplash = document.getElementById('loading-splash');

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    
    if (loadingSplash) {
      loadingSplash.style.opacity = '0';
      loadingSplash.style.transition = 'opacity 0.3s ease-out';
      setTimeout(function() {
        loadingSplash.remove();
      }, 300);
    }
    
    await appRunner.runApp();
  }
});