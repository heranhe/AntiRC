import { execSync } from "child_process";
import fs from "fs";
import path from "path";

const CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const BASE_URL = "http://127.0.0.1:3000/render-single";
const PROJECT_ROOT = path.resolve("..");
const OUTPUT_ROOT = path.join(PROJECT_ROOT, "screenshots-output");

const JOBS = [
  {
    folder: "01-Midnight-Glow-Pro",
    preset: "midnight-glow-pro",
    slides: [
      { index: 0, filename: "01_RemoteControl.png" },
      { index: 1, filename: "02_CloudRelay.png" },
      { index: 2, filename: "03_FastConnect.png" },
      { index: 3, filename: "04_SessionHub.png" },
    ],
  },
  {
    folder: "02-Liquid-Glass-Aurora",
    preset: "liquid-glass-aurora",
    slides: [
      { index: 0, filename: "01_AIAssistant.png" },
      { index: 1, filename: "02_SeamlessRelay.png" },
      { index: 2, filename: "03_EffortlessPairing.png" },
      { index: 3, filename: "04_DeviceHub.png" },
    ],
  },
];

console.log("🚀 开始批量渲染导出两套风格的 App Store 截图...");

for (const job of JOBS) {
  const dir = path.join(OUTPUT_ROOT, job.folder);
  fs.mkdirSync(dir, { recursive: true });
  console.log(`\n🎨 正在生成风格 [${job.folder}]...`);

  for (const item of job.slides) {
    const dest = path.join(dir, item.filename);
    const url = `${BASE_URL}?preset=${job.preset}&index=${item.index}&locale=zh-Hans`;
    console.log(`   📸 渲染 ${item.filename} (index: ${item.index})...`);

    const cmd = `"${CHROME_PATH}" --headless=new --screenshot="${dest}" --window-size=1320,2868 --virtual-time-budget=3000 --hide-scrollbars "${url}"`;
    try {
      execSync(cmd, { stdio: "ignore" });
      const stats = fs.statSync(dest);
      console.log(`   ✅ 成功导出: ${item.filename} (${(stats.size / 1024).toFixed(1)} KB)`);
    } catch (err) {
      console.error(`   ❌ 导出失败: ${item.filename}`, err.message);
    }
  }
}

console.log("\n🎉 全部 8 张高清 App Store 截图导出完成！");
