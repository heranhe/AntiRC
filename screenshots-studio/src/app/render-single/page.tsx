"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import { DeckCanvas, getCanvas } from "@/components/editor/slide-canvas";
import { DEFAULT_SCREENSHOT_FONT_ID, SCREENSHOT_FONTS, themeById } from "@/lib/constants";
import type { ProjectState } from "@/lib/types";

// 预设配置
import midnightPreset from "../../../presets/midnight-glow-pro.json";
import auroraPreset from "../../../presets/liquid-glass-aurora.json";

const PRESETS: Record<string, ProjectState> = {
  "midnight-glow-pro": midnightPreset as unknown as ProjectState,
  "liquid-glass-aurora": auroraPreset as unknown as ProjectState,
};

function RenderSingleContent() {
  const searchParams = useSearchParams();
  const presetKey = searchParams.get("preset") || "midnight-glow-pro";
  const index = parseInt(searchParams.get("index") || "0", 10);
  const locale = searchParams.get("locale") || "zh-Hans";

  const project = PRESETS[presetKey] || PRESETS["midnight-glow-pro"];
  const device = project.device || "iphone";
  const orientation = project.orientation || "portrait";
  const slides = project.slidesByDevice[device] || [];
  const exportCanvas = getCanvas(device, orientation);

  return (
    <div
      style={{
        width: exportCanvas.cW,
        height: exportCanvas.cH,
        overflow: "hidden",
        position: "relative",
        margin: 0,
        padding: 0,
        backgroundColor: themeById(project.themeId).bg,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: -index * exportCanvas.cW,
          top: 0,
          width: exportCanvas.cW * slides.length,
          height: exportCanvas.cH,
        }}
      >
        <DeckCanvas
          slides={slides}
          device={device}
          orientation={orientation}
          theme={themeById(project.themeId)}
          locale={locale}
          appName={project.appName}
          appIcon={project.appIcon}
          fontFamily={SCREENSHOT_FONTS[DEFAULT_SCREENSHOT_FONT_ID].family}
          connectedCanvas={project.connectedCanvas ?? true}
          hideEmpty
        />
      </div>
    </div>
  );
}

export default function RenderSinglePage() {
  return (
    <React.Suspense fallback={<div style={{ width: 1320, height: 2868, background: "#07080B" }} />}>
      <RenderSingleContent />
    </React.Suspense>
  );
}
