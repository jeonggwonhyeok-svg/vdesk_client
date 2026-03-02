# GitHub 설정 가이드

## 1. GitHub CLI 설치

```bash
brew install gh
```

## 2. GitHub 로그인

```bash
gh auth login
```

### 로그인 절차

1. **Where do you use GitHub?** → `GitHub.com` 선택
2. **What is your preferred protocol?** → `HTTPS` 선택
3. **Authenticate Git with your GitHub credentials?** → `Yes`
4. **How would you like to authenticate?** → `Login with a web browser` 선택
5. 터미널에 **일회용 코드** 표시됨 (예: `ABCD-1234`)
6. 브라우저가 자동으로 열림 → 코드 입력 → **Authorize** 클릭
7. 터미널에 `Logged in as 사용자명` 출력되면 완료

### 로그인 확인

```bash
gh auth status
```

## 3. 프로젝트 리모트 설정

### 메인 프로젝트 (onedesk)

```bash
cd /Users/toho/Project/onedesk
git remote set-url origin https://github.com/jeonggwonhyeok-svg/onedesk.git
```

### 서브모듈 (hbb_common)

```bash
# .gitmodules 변경
git config --file .gitmodules submodule.libs/hbb_common.url https://github.com/jeonggwonhyeok-svg/hbb_common.git

# 서브모듈 내부 remote 변경
cd libs/hbb_common
git remote set-url origin https://github.com/jeonggwonhyeok-svg/hbb_common.git
cd ../..
```

### 리모트 확인

```bash
# 메인 프로젝트
git remote -v

# 서브모듈
cd libs/hbb_common && git remote -v && cd ../..
```

## 4. Push

### 서브모듈 먼저 push (필수)

```bash
cd libs/hbb_common
git push -u origin HEAD:master --force
cd ../..
```

### 메인 프로젝트 push

```bash
git push -u origin master --force
```

## 5. 참고

- 서브모듈을 먼저 push해야 GitHub Actions 빌드 시 서브모듈 클론이 정상 동작함
- `gh auth login` 한 번 하면 이후 push/pull 시 자동 인증됨
- 인증 해제: `gh auth logout`
