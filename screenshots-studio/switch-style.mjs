import fs from "fs";
import path from "path";

const target = process.argv[2] || "midnight";
const presets = {
  midnight: "presets/midnight-glow-pro.json",
  aurora: "presets/liquid-glass-aurora.json",
};

const file = presets[target] || presets.midnight;
if (fs.existsSync(file)) {
  fs.copyFileSync(file, "app-store-screenshots.json");
  console.log(`✅ 已成功将网页编辑器切换为 [${target}] 风格预设！`);
  console.log(`🌐 刷新 http://localhost:3000 即可直接查看与微调。`);
} else {
  console.error(`❌ 未找到预设文件: ${file}`);
}
