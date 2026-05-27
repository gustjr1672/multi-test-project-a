#!/bin/bash

# 1. 현재 구동 중인 타겟 확인 (Project A용 이름 사용)
IS_GREEN=$(docker ps -q -f name=api-green-a)

if [ -n "$IS_GREEN" ]; then
    CURRENT_TARGET="api-green-a"
    NEW_TARGET="api-blue-a"
    OLD_TARGET="api-green-a"
    NEW_PORT="8080"
else
    CURRENT_TARGET="api-blue-a"
    NEW_TARGET="api-green-a"
    OLD_TARGET="api-blue-a"
    NEW_PORT="8081"
fi

echo "CURRENT_TARGET=[$CURRENT_TARGET]"
echo "🚀 배포 시작: Project A 새로운 버전($NEW_TARGET) 준비"

export IMAGE_TAG="v$(date +%s)"

# 2. 새로운 타겟만 백그라운드로 빌드 및 실행
docker compose up -d --build $NEW_TARGET

# 3. 헬스 체크
echo "헬스 체크 진행 중 ($NEW_TARGET 내부 포트 8080 확인)"
for i in {1..10}
do
    STATUS_CODE=$(curl -o /dev/null -s -w "%{http_code}\n" http://127.0.0.1:$NEW_PORT/health)
    
    if [ "$STATUS_CODE" == "200" ]; then
        echo "✅ 헬스 체크 통과!"
        break
    fi
    echo "대기 중... ($i/10)"
    sleep 2
done

sleep 3

if [ "$STATUS_CODE" != "200" ]; then
    echo "🚨 헬스 체크 실패! 새 컨테이너를 내립니다."
    docker compose stop $NEW_TARGET
    exit 1
fi

# ==================================================
# ⭐️ 4. Master Nginx 스위칭 (동기화 지연 완벽 차단)
# ==================================================
echo "🔄 트래픽을 $NEW_TARGET($NEW_PORT) 포트로 전환합니다."

# Master Nginx의 설정 파일 절대 경로
MASTER_CONF="/home/jhs/master-nginx/master-nginx.conf"

# 1. 원본 파일의 도커 마운트 연결(Inode)이 깨지지 않도록 tmp 파일을 거쳐 덮어쓰기 (sed -i 사용 금지!)
sed "s/server 127.0.0.1:[0-9]*; # project-a/server 127.0.0.1:$NEW_PORT; # project-a/g" $MASTER_CONF > master-nginx.tmp
cat master-nginx.tmp > $MASTER_CONF
rm master-nginx.tmp

# 2. 동기화 지연 차단: 수정한 파일 데이터를 외부의 Master Nginx 컨테이너 내부에 직접 꽂아 넣기
# (docker compose exec가 아니라 docker exec를 사용하므로, 파이프 입력을 받기 위해 -i 옵션이 필수입니다)
cat $MASTER_CONF | docker exec -i master-nginx sh -c 'cat > /etc/nginx/nginx.conf'

# 3. 문법 검사 및 리로드
docker exec master-nginx nginx -t
docker exec master-nginx nginx -s reload

echo "Nginx 교대 대기 중... (2초)"
sleep 2

# ==================================================
# 5. 구버전 종료
# ==================================================
echo "🛑 기존 버전($OLD_TARGET) 종료를 요청합니다."
docker compose stop $OLD_TARGET &
STOP_PID=$!
ELAPSED=0

while kill -0 $STOP_PID 2>/dev/null; do
    echo -ne "\r⏳ 처리 중인 남은 요청 대기 중... ${ELAPSED}초 경과\t"
    sleep 1
    ((ELAPSED++))
done

echo -e "\n✅ $OLD_TARGET 종료 완료! (총 ${ELAPSED}초 소요)"

echo "IMAGE_TAG=${IMAGE_TAG}" > .env
echo "LAST_TARGET=${NEW_TARGET}" >> .env
echo "🎉 Project A 무중단 배포 완료!"