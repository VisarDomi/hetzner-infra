import { defineConfig } from 'vite';
import { sveltekit } from '@sveltejs/kit/vite';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		proxy: {
			'/data.json': {
				target: 'http://localhost:3000',
				changeOrigin: true
			}
		}
	}
});
