# 游戏音效

本目录的 19 个 WAV 均由 `generate_audio.py` 原创合成，没有使用第三方录音或外部音效包。属于风格化声音，不是实地录制。

- `seed`：播种成功；`build`：建筑建成；`develop`：地形开发；`road`：道路完成。
- `draw`：抽牌；`select`：选择卡牌或地块；`rotate`：旋转预览；`cancel`：主动取消。
- `warning`：无效操作；`reward`：道路闭合、建筑奖励、发现洪山装饰等金字通知。
- `turn`：回合开始与结算后的换人；`victory`：结束游戏。
- `weather`、`rainbow`：天气卡成功生效；`thunder`：台风期间间隔出现的低沉雷声。
- `rain`、`storm`、`sand`、`dry`：12 秒立体声循环环境音。

直接打开 `preview.html` 可逐项试听。试听页播放的是原始素材；游戏中的音量更低，并按操作优先级和天气状态混合。

## 集成

`scripts/game_audio.gd` 负责统一播放、六路短音效上限、优先级、重复提示限频、音量设置和环境音淡入淡出。
成功音效在卡牌提交成功后触发；预览模型、逐朵花生长和失败操作不播放成功音效。
雨季与台风共用一条雨声层，台风另加风声和间隔雷声。旱季清除湿润天气后会停止雨声，兼容天气保留各自的环境层。
天气到期、彩虹清除、游戏结束或重新开局时会关闭对应环境音。静音后恢复会重新读取当前天气。

开始页和对局右上角均提供声音设置，可单独调整背景音乐、操作提示、天气环境，并可全部静音。
设置保存到 `user://audio_settings.cfg`；开始页原有音乐按钮与音乐设置同步。

## 生成与验证

```text
python assets/audio/generate_audio.py
python -m unittest discover -s tests -p test_audio_assets.py
godot --headless --path . --script tests/audio_smoke.gd
godot --headless --path . --script tests/title_screen_smoke.gd
```

素材使用 24 kHz、16-bit PCM；短音效为单声道，环境音为立体声。测试检查素材非静音、峰值余量、首尾过渡，以及游戏中的成功/失败反馈、天气切换、到期和静音恢复。
无窗口测试验证播放状态与逻辑，实际听感和扬声器上的最终音量仍应通过试听和实机体验确认。
