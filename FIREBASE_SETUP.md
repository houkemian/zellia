# Firebase 第三方登录配置说明（中文版）

当前项目已支持通过 Firebase 代理第三方登录，提供：

- Google 登录
- Microsoft 登录

## 1）移动端配置（Flutter）

- 在 `mobile/pubspec.yaml` 中添加依赖：
  - `firebase_core`
  - `firebase_auth`
  - `google_sign_in`
- 确保资源文件已加入：
  - `assets/icons/google_logo.png`
  - `assets/icons/microsoft_logo.png`
- App 启动时先初始化 Firebase，再进入登录页。

### Android

- 将 `google-services.json` 放到：
  - `mobile/android/app/google-services.json`
- 在 Firebase Console 中启用 Google 登录。
- Microsoft 登录配置：
  - Firebase Console -> Authentication -> Sign-in method -> Microsoft
  - 按实际租户（tenant）和应用（client）信息填写配置。

### iOS

- 将 `GoogleService-Info.plist` 放到：
  - `mobile/ios/Runner/GoogleService-Info.plist`
- 按 Firebase 官方步骤配置 URL Schemes 等 iOS 关联项。

## 2）后端配置（FastAPI）

后端已实现接口：

- `POST /auth/firebase-login`

请求体：

```json
{
  "provider": "google | microsoft",
  "id_token": "firebase-id-token",
  "access_token": "optional-oauth-access-token"
}
```

返回体：

```json
{
  "access_token": "app-jwt-token",
  "token_type": "bearer"
}
```

### 环境变量

在后端 `.env` 中设置：

- `FIREBASE_CREDENTIALS_PATH=/absolute/path/to/firebase-service-account.json`

若未设置，后端会尝试使用运行环境中的默认 Firebase 凭据（ADC）。

## 3）Firebase 服务账号（Service Account）

- 在 Firebase Console / Google Cloud 中创建服务账号。
- 下载 JSON 密钥文件。
- 该文件属于敏感凭据，禁止提交到 git。
- 后端运行时将 `FIREBASE_CREDENTIALS_PATH` 指向该 JSON 文件。

## 4）通用校验规则

- `provider` 仅允许：`google` 或 `microsoft`。
- 后端使用 Firebase Admin SDK 校验 `id_token`。
- 后端会校验 token 中的 provider 声明：
  - Google -> `google.com`
  - Microsoft -> `microsoft.com`

## 5）常见问题排查

- `503 Firebase auth is not configured`
  - 检查 `FIREBASE_CREDENTIALS_PATH` 是否正确、文件是否可读。
- `401 Invalid Firebase token`
  - 确认移动端 Firebase 项目与后端验证使用的是同一个项目。
- `Provider mismatch`
  - 确认前端按钮传入的 `provider` 与实际登录来源一致（Google/Microsoft）。
