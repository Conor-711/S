Product Requirement Document (PRD): URL Ingestion Engine
项目	内容
Feature Name	URL Ingestion Engine (URL 摄取引擎)
Version	v1.0 (Draft)
Platform	macOS (Swift / SwiftUI)
Status	Planning
Core Goal	将外部 URL 内容转化为内部可执行的 Visual Steps，实现“信息 -> 行动”的自动转换。
1. 功能概述 (Overview)
用户通过 AI Navigator 的输入框粘贴 URL（支持批量），系统自动识别 URL 类型（Twitter/X, YouTube, General Web），调用对应的 API（Grok, Gemini, Web Crawler）提取内容。
提取后的内容经过 "Actionability Filter" (可执行性过滤器) 校验：
若是教程/指南 -> 生成 Guidebook。
若是新闻/观点/搞笑内容 -> 拦截并提示（除非用户有明确指令）。
2. 用户交互流程 (User Flow)
输入阶段：
用户呼出 AI Navigator，在搜索框/输入框粘贴一个或多个 URL。
(可选) 用户在 URL 后附加文本指令（例如：https://... 帮我总结这个观点的反驳话术）。
解析与确认阶段：
系统后台进行队列处理。
短链处理：如果是 bit.ly 等短链，自动解析为长链。
时长预警：(YouTube 场景) 如果视频时长 > 2小时，弹窗提示：“视频过长，处理可能较慢或消耗大量 Token，是否继续？”
处理阶段 (后台)：
UI 显示处理进度条 (e.g., "Analyzing Tweet...", "Watching Video...", "Parsing HTML...").
结果反馈阶段：
成功 (Actionable)：直接展开 Stack View，显示步骤 1、2、3。
拦截 (Not Actionable)：Toast 提示：“该内容主要为观点或新闻，未检测到操作步骤。” (仅在无用户附加指令时触发)。
失败 (Error)：Toast 提示错误类型 (e.g., "无法访问付费内容", "URL 无效").
3. 技术逻辑详述 (Functional Specifications)
3.1 路由层 (The Router)
输入：URL String List.
短链解析 (Shortlink Resolver)：
检测域名是否在 ShortURL_Blocklist 中。
执行 HTTP HEAD 请求获取 Location header。
递归解析直到获得最终 URL。
分类正则 (Regex Classifiers)：
Type A (Tweet): twitter.com, x.com
Type B (YouTube): youtube.com, youtu.be
Type C (General): All others.
3.2 摄取管道 (Ingestion Pipelines)
Pipeline A: Twitter/X (Powered by Grok)
API: Grok API (xAI).
逻辑：
请求 Grok 分析该 URL。
Prompt 策略：要求 Grok 提取推文完整正文 (Text) 以及附带图片的描述 (Image Captioning)。
混合内容处理：
如果 Grok 返回的数据表明推文中包含 视频链接，则提取该视频 URL，同时触发 Pipeline B (YouTube/Video Analysis)，并将两者结果合并。
Output: RawContent_Text + Image_Context.
Pipeline B: YouTube (Powered by Gemini)
API: Gemini 1.5 Pro / Flash (Google Vertex AI).
前置检查：调用 YouTube Data API (或轻量级 oEmbed) 获取视频时长。
if duration > 120 mins -> 触发前端确认弹窗。
逻辑：
Native Video Analysis: 将视频流 (Stream) 或 Buffer 投喂给 Gemini 的 Context Window。
Prompt: "Watch this video and extract a step-by-step technical tutorial. Ignore intro, outro, and sponsor segments."
Output: Structured_Steps_JSON.
Pipeline C: General Web (Simple Crawler)
技术栈: Swift Native URLSession (非 Headless Browser)。
逻辑：
GET 请求获取 HTML。
Paywall Check: 检查 HTTP 状态码 (401/403) 或 HTML 中是否存在常见的 Paywall 标记 (e.g., <meta name="paywall">, 特定 class)。
若付费墙 -> 抛出错误 Error_Paywall。
清洗: 去除 <script>, <style>, <nav>, <footer>，仅保留主要 <article> 或 <body> 文本。
混合内容优先级: 若网页包含 YouTube 嵌入，忽略视频，仅抓取文字（根据需求 5）。
Output: Cleaned_HTML_Text.
3.3 价值判断器 (The Actionability Filter)
输入: Extracted_Content + User_Prompt (Optional).
判断逻辑:
Scenario 1: 用户有附加 Prompt
Action: 跳过价值判断，直接强制生成 (Force Generation)。
例子: URL 是一个新闻，用户说“把这个新闻的发布流程整理出来”，AI 必须执行。
Scenario 2: 仅有 URL
Action: 调用 LLM (Lightweight Model) 进行二分类判断。
System Prompt:
"Analyze the following content. Does it contain a repeatable workflow, tutorial, or software instruction?
If YES: Output JSON with steps.
If NO (it's news, opinion, humor, theory): Output STATUS: REJECT."
反馈:
STATUS: REJECT -> 前端显示 Toast: "Content is informational (News/Opinion) and has no actionable steps."
4. 数据模型 (Data Structures)
输入对象
code
Swift
struct IngestionRequest {
    let id: UUID
    let rawURLs: [String] // 支持批量
    let userInstruction: String? // 用户附加指令
}
路由枚举
code
Swift
enum ContentSource {
    case twitter(hasVideo: Bool)
    case youtube(duration: TimeInterval)
    case web
}
错误定义
code
Swift
enum IngestionError: Error {
    case paywallDetected      // "付费内容无法抓取"
    case timeout              // "请求超时"
    case notActionable        // "未检测到可执行步骤"
    case videoTooLong         // "视频超过2小时限制"
    case invalidURL
}
5. UI/UX 细节规范
Queue Visualization (队列可视化)
当用户粘贴多个 URL 时，AI Navigator 底部出现一个小型的 "Processing Queue" 面板。
状态图标：
🔵 Spinner: Analysis in progress...
🟢 Checkmark: Ready.
🔴 X Mark: Failed/Rejected.
Video Confirmation Dialog (视频时长确认)
Title: "Long Video Detected"
Body: "This video is over 2 hours long. Analyzing it requires significant AI resources."
Buttons: [Cancel] [Analyze Anyway]
Language Standardization
无论来源是日语推文还是法语博客，最终的 Steps 默认生成英文 (English)。
(未来可配置，目前硬编码为 English)。
6. 风险评估与应对 (Risk & Mitigation)
风险点	应对策略
Grok API 限制	若 Grok 暂时无法直接通过 API 读取 URL，需建立中间层：使用轻量级 Scraper 获取推文 Text/Image Raw Data，再发给 Grok 分析。
Simple HTML 抓取失败	对于 SPA (React/Vue) 网站，Simple Crawler 抓不到内容。策略：第一版接受此限制，报错提示用户“无法读取动态网页，请截图使用 Context Capsule”。
Gemini 视频成本	视频分析 Token 消耗巨大。策略：严格执行 2 小时限制；在 System Prompt 中强调 "Summarize efficiently"。
Anti-Scraping	Twitter/X 和 YouTube 对 IP 封锁严格。策略：使用官方 API (Paid Plans) 或 代理池 (Proxy Pool) 确保稳定性。