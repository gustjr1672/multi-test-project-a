#!/bin/bash

# 1. 현재 Nginx가 바라보고 있는 타겟 확인
IS_GREEN=$(docker ps -q -f name=api-green)

if [ -n "$IS_GREEN" ]; then
    CURRENT_TARGET="api-green"
    NEW_TARGET="api-blue"
    OLD_TARGET="api-green"
    NEW_PORT="8080"
else
    CURRENT_TARGET="api-blue"
    NEW_TARGET="api-green"
    OLD_TARGET="api-blue"
    NEW_PORT="8081"
fi

echo "CURRENT_TARGET=[$CURRENT_TARGET]"
echo " 배포 시작: 새로운 버전($NEW_TARGET)을 준비합니다."


# 2. 이미지 태그 생성 및 환경변수 주입 (Compose가 사용할 수 있도록)
export IMAGE_TAG="v$(date +%s)"


# 3. 새로운 타겟만 백그라운드로 빌드 및 실행 (이때 기존 타겟은 건드리지 않음)
docker compose up -d --build $NEW_TARGET


# 4. 헬스 체크  
echo "헬스 체크 진행 중 ($NEW_TARGET 내부 포트 8080 확인)"
for i in {1..10}
do
    STATUS_CODE=$(docker compose exec -T nginx-proxy curl -o /dev/null -s -w "%{http_code}\n" http://$NEW_TARGET:8080/health)
    
    if [ "$STATUS_CODE" == "200" ]; then
        echo "헬스 체크 통과!"
        break
    fi
    echo "대기 중... ($i/10)"
    sleep 2
done


echo "도커 네트워크 및 C# 앱 워밍업 대기 중... (3초)"
sleep 3

if [ "$STATUS_CODE" != "200" ]; then
    echo "헬스 체크 실패! 새 컨테이너를 내립니다."
    docker compose stop $NEW_TARGET
    exit 1
fi

# 5. Nginx 스위칭
echo " Nginx 트래픽을 $NEW_TARGET 으로 전환합니다."

sed "s/server .*:8080;/server $NEW_TARGET:8080;/g" nginx.conf > nginx.tmp
cat nginx.tmp > nginx.conf
rm nginx.tmp

cat nginx.conf | docker compose exec -T nginx-proxy sh -c 'cat > /etc/nginx/nginx.conf' # 가상머신 특유의 '파일 동기화 지연(Sync Delay)' 현상 때문에 추가함

# 문법 검사: Nginx에게 대본에 문제 없는지 먼저 확인받음
docker compose exec -T nginx-proxy nginx -t

# 리로드: 완벽하게 확인된 상태에서 새로고침!
docker compose exec -T nginx-proxy nginx -s reload

echo "Nginx 교대 대기 중... (2초)"
sleep 2

# 6. 구버전 내리기
echo " 트래픽 전환 완료. 구버전($OLD_TARGET)을 종료합니다."
docker compose stop $OLD_TARGET &

# 6-1. 구버전 내려가는지 시간초 확인
STOP_PID=$!

# 초시계 변수 초기화
ELAPSED=0

# 해당 프로세스가 살아있는 동안 1초씩 대기하며 타이머 출력
while kill -0 $STOP_PID 2>/dev/null; do
    echo -ne "\r⏳ 처리 중인 남은 요청을 기다리는 중... ${ELAPSED}초 경과\t"
    sleep 1
    ((ELAPSED++))
done

# 종료 완료 메시지 출력
echo -e "\n✅ $OLD_TARGET 종료가 완벽하게 완료되었습니다! (총 ${ELAPSED}초 소요)"


#재부팅 시에 last버전을 볼 수 있도록 env파일에 기록
echo "IMAGE_TAG=${IMAGE_TAG}" > .env
echo "LAST_TARGET=${NEW_TARGET}" >> .env

echo " 무중단 배포($NEW_TARGET)가 완료되었습니다!"