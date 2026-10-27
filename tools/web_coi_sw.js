// Служебный помощник страницы (service worker) для многопоточной версии игры.
// Потокам браузера нужна «изоляция» страницы — заголовки COOP/COEP. GitHub Pages
// не даёт задать свои заголовки, поэтому их добавляет этот помощник ко всем
// ответам сайта. Ничего не кэширует: каждая загрузка — свежая версия игры.
// Копируется в web/coi.sw.js скриптом tools/build_web.sh.

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
	const request = event.request;
	// Запрос «только из кэша» к чужому сайту браузер не разрешает переписывать.
	if (request.cache === 'only-if-cached' && request.mode !== 'same-origin') {
		return;
	}
	if (new URL(request.url).origin !== self.location.origin) {
		return;
	}
	event.respondWith(fetch(request).then((response) => {
		if (response.status === 0) {
			return response;
		}
		const headers = new Headers(response.headers);
		headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
		headers.set('Cross-Origin-Opener-Policy', 'same-origin');
		return new Response(response.body, {
			status: response.status,
			statusText: response.statusText,
			headers,
		});
	}));
});
