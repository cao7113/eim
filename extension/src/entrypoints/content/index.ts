import { mount, unmount } from 'svelte';
import App from './App.svelte';
import './style.css';

export default defineContentScript({
    matches: ['<all_urls>'],
    cssInjectionMode: 'ui',

    async main(ctx) {
        const ui = await createShadowRootUi(ctx, {
            name: 'eim-ui',
            position: 'overlay',
            anchor: 'body',
            onMount: (container) => mount(App, { target: container }),
            onRemove: (app) => {
                if (app) unmount(app);
            },
        });
        ui.mount();
    },
});