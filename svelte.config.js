import adapter from '@sveltejs/adapter-node';

const config = {
	kit: {
		adapter: adapter({ out: 'build' }),
		csrf: {
			checkOrigin: false
		}
	}
};

export default config;
