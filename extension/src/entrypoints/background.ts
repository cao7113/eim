// export default defineBackground(() => {
//   console.log('Hello background!', { id: browser.runtime.id });
// });


export default defineBackground(() => {
  browser.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg?.type === 'translate') {
      mockTranslate(msg.text).then(sendResponse);
      return true; // 异步回复，必须返回 true
    }
  });
});

async function mockTranslate(text: string) {
  await new Promise((r) => setTimeout(r, 400)); // 模拟网络延迟
  return { result: `[mock] ${text} 的释义` };
}