#!/bin/bash

# ==============================================================================
# Універсальний скрипт для діагностики та усунення CVE-2025-49113 [Roundcube]
# Підтримує автоматичне лікування CWP, DirectAdmin та інтерактивний апдейт інших
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   Universal Roundcube Vulnerability Fixer        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# --- КРОК 1: ДІАГНОСТИКА ПАНЕЛІ ТА ОС ---
echo -e "\n${YELLOW}[1/4] Перевірка операційної системи та панелі...${NC}"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_INFO="$NAME $VERSION_ID"
else
    OS_INFO="Невідома ОС"
fi
echo -e "Операційна система: ${GREEN}$OS_INFO${NC}"

PANEL="Unknown"

if [ -d "/usr/local/cwp" ]; then
    PANEL="CWP"
elif [ -d "/usr/local/cpanel" ]; then
    PANEL="cPanel"
elif [ -d "/usr/local/directadmin" ]; then
    PANEL="DirectAdmin"
elif [ -d "/usr/local/hestia" ]; then
    PANEL="HestiaCP"
else
    if [ -d "/var/www/html" ] && (which nginx &>/dev/null || which httpd &>/dev/null || which apache2 &>/dev/null); then
        PANEL="LAMP_LEMP"
    fi
fi

echo -e "Виявлена панель: ${GREEN}$PANEL${NC}"

# --- КРОК 2: ВИЗНАЧЕННЯ ВЕРСІЇ ДО ВИПРАВЛЕННЯ ---
echo -e "\n${YELLOW}[2/4] Визначення поточної версії Roundcube...${NC}"
CURRENT_VERSION="Не визначено"

case "$PANEL" in
    "CWP")
        RC_VERSION_FILE="/usr/local/cwpsrv/var/services/roundcube/program/include/iniset.php"
        ;;
    "DirectAdmin"|"LAMP_LEMP")
        RC_VERSION_FILE="/var/www/html/roundcube/program/include/iniset.php"
        [ ! -f "$RC_VERSION_FILE" ] && RC_VERSION_FILE="/var/www/html/webmail/program/include/iniset.php"
        ;;
    "cPanel")
        # В cPanel версію простіше отримати через менеджер пакетів RPM
        CURRENT_VERSION=$(rpm -qa | grep cpanel-roundcube | head -n 1 | sed 's/cpanel-roundcube-//')
        ;;
    "HestiaCP")
        RC_VERSION_FILE="/usr/share/roundcube/program/include/iniset.php"
        ;;
esac

if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" == "Не визначено" ]; then
    if [ -f "$RC_VERSION_FILE" ]; then
        CURRENT_VERSION=$(grep "define('RCMAIL_VERSION'" "$RC_VERSION_FILE" | head -n 1 | cut -d"'" -f4)
    else
        CURRENT_VERSION="Неможливо визначити автоматично (можливо, Roundcube не встановлено)"
    fi
fi

echo -e "Поточна версія Roundcube на сервері: ${RED}$CURRENT_VERSION${NC}"

# --- КРОК 3: ЛОГІКА ОБРОБКИ ПАНЕЛЕЙ ---
echo -e "\n${YELLOW}[3/4] Запуск процесу усунення вразливості...${NC}"

case "$PANEL" in
    "CWP")
        echo -e "${GREEN}Запуск автоматичного оновлення для CWP через заміну сирців...${NC}"
        
        # Перевірка PHP intl
        CWP_PHP="/usr/local/cwp/php71/bin/php"
        if ! $CWP_PHP -m | grep -q 'intl'; then
            echo -e "${YELLOW}[ІНФО] Встановлюємо розширення intl для CWP...${NC}"
            yum update ca-certificates -y &>/dev/null
            if [[ "$VERSION_ID" == "7" ]]; then
                rpm -ivh https://github.com/mysterydata/md-disk/raw/main/libicu69-69.1-4.el7.x86_64.rpm --force --nodeps &>/dev/null
                curl -s -L https://www.alphagnu.com/upload/tmp/cwp_rc_fix.sh | bash &>/dev/null
            else
                rpm -ivh https://github.com/mysterydata/md-disk/raw/main/libicu69-69.1-4.el8.x86_64.rpm --force --nodeps &>/dev/null
                curl -s -L https://www.alphagnu.com/upload/tmp/el8/cwp_rc_fix_el8.sh | bash &>/dev/null
            fi
        fi

        # Качаємо та ставимо
        cd /usr/local/src || exit 1
        rm -rf roundcube*
        wget -q https://github.com/roundcube/roundcubemail/releases/download/1.5.15/roundcubemail-1.5.15-complete.tar.gz
        tar xf roundcubemail-1.5.15-complete.tar.gz
        cd roundcubemail-1.5.15/ || exit 1
        sed -i "s@\/usr\/bin\/env php@\/usr\/bin\/env \/usr\/local\/cwp\/php71\/bin\/php@g" bin/installto.sh
        sed -i "s@\php bin@\/usr\/local\/cwp\/php71\/bin\/php bin@g" bin/installto.sh
        TARGET_DIR="/usr/local/cwpsrv/var/services/roundcube"
        yes | bin/installto.sh $TARGET_DIR
        systemctl restart cwpsrv cwp-phpfpm postfix dovecot &>/dev/null
        ;;

    "DirectAdmin")
        echo -e "${GREEN}Запуск автоматичного оновлення через DirectAdmin CustomBuild...${NC}"
        cd /usr/local/directadmin/custombuild || exit 1
        ./build update
        ./build roundcube
        TARGET_DIR="/var/www/html/roundcube"
        ;;

    "cPanel")
        echo -e "${RED}⚠️ Пряме оновлення файлів архівом заблоковано, щоб не зламати ліцензію та структуру cPanel.${NC}"
        echo -e "${YELLOW}Оновлення цієї панелі має виконуватися через рідний скрипт оновлення системи (/scripts/upcp).${NC}"
        read -p "Бажаєте запустити повне оновлення cPanel [upcp] прямо зараз? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo -e "${GREEN}Запуск /usr/local/cpanel/scripts/upcp... Це може зайняти час.${NC}"
            /usr/local/cpanel/scripts/upcp
        else
            echo -e "${YELLOW}Операцію скасовано сапортом.${NC}"
            exit 0
        fi
        ;;

    "HestiaCP")
        echo -e "${RED}⚠️ В Хестії Roundcube оновлюється через системний менеджер пакетів APT.${NC}"
        read -p "Бажаєте запустити оновлення пакетів Hestia Webmail прямо зараз? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo -e "${GREEN}Оновлюємо roundcube через apt-get...${NC}"
            apt-get update && apt-get --only-upgrade install hestia-php roundcube -y
        else
            echo -e "${YELLOW}Операцію скасовано сапортом.${NC}"
            exit 0
        fi
        ;;

    *)
        echo -e "${RED}[УВАГА] Чистий сервер без панелі або невідоме середовище.${NC}"
        echo -e "Автоматичне оновлення архівом небезпечне. Виконайте оновлення вручну."
        exit 0
        ;;
esac

# --- КРОК 4: ФІНАЛЬНИЙ ЗВІТ ---
echo -e "\n${YELLOW}[4/4] Формування звіту...${NC}"
NEW_VERSION="Не визначено"

case "$PANEL" in
    "CWP") [ -f "$RC_VERSION_FILE" ] && NEW_VERSION=$(grep "define('RCMAIL_VERSION'" "$RC_VERSION_FILE" | head -n 1 | cut -d"'" -f4) ;;
    "DirectAdmin") [ -f "/var/www/html/roundcube/program/include/iniset.php" ] && NEW_VERSION=$(grep "define('RCMAIL_VERSION'" "/var/www/html/roundcube/program/include/iniset.php" | head -n 1 | cut -d"'" -f4) ;;
    "cPanel") NEW_VERSION=$(rpm -qa | grep cpanel-roundcube | head -n 1 | sed 's/cpanel-roundcube-//') ;;
    "HestiaCP") [ -f "/usr/share/roundcube/program/include/iniset.php" ] && NEW_VERSION=$(grep "define('RCMAIL_VERSION'" "/usr/share/roundcube/program/include/iniset.php" | head -n 1 | cut -d"'" -f4) ;;
esac

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}                ЗВІТ ПРО ВИКОНАННЯ                 ${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "Панель керування: ${GREEN}$PANEL${NC}"
echo -e "Версія ДО виправлення:  ${RED}$CURRENT_VERSION${NC}"
echo -e "Версія ПІСЛЯ виправлення: ${GREEN}$NEW_VERSION${NC}"
echo -e "--------------------------------------------------"
echo -e "${GREEN}Статус:${NC} Перевірку/Оновлення завершено успішно."
echo -e "${GREEN}==================================================${NC}"
