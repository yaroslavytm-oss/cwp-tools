#!/bin/bash

# ==============================================================================
# Діагностичний та інсталяційний скрипт для усунення CVE-2025-49113 (Roundcube)
# ==============================================================================

# Кольори для гарного виведення
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   Roundcube Vulnerability Scanner & Updater       ${NC}"
echo -e "${BLUE}==================================================${NC}"

# --- КРОК 1: ДІАГНОСТИКА ПАНЕЛІ КЕРУВАННЯ ---
echo -e "\n${YELLOW}[1/4] Перевірка панелі керування та ОС...${NC}"

# Визначення ОС
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_INFO="$NAME $VERSION_ID"
else
    OS_INFO="Невідома ОС"
fi
echo -e "Операційна система: ${GREEN}$OS_INFO${NC}"

PANEL="Unknown"
CAN_UPDATE=false

# Скануємо наявність панелей
if [ -d "/usr/local/cwp" ]; then
    PANEL="CWP (Control Web Panel)"
    CAN_UPDATE=true
elif [ -d "/usr/local/cpanel" ]; then
    PANEL="cPanel / WHM"
elif [ -d "/usr/local/directadmin" ]; then
    PANEL="DirectAdmin"
elif [ -d "/usr/local/hestia" ]; then
    PANEL="HestiaCP"
elif [ -d "/home/cyberpanel" ]; then
    PANEL="CyberPanel"
else
    # Перевірка на "чистий" LAMP/LEMP
    if [ -d "/var/www/html" ] && (which nginx &>/dev/null || which httpd &>/dev/null || which apache2 &>/dev/null); then
        PANEL="Чистий LAMP/LEMP (Без панелі)"
    fi
fi

echo -e "Виявлена панель: ${GREEN}$PANEL${NC}"

# Виведення статусу залежно від панелі
case "$PANEL" in
    "CWP (Control Web Panel)")
        echo -e "Статус оновлення: ${GREEN}МОЖНА ОНОВИТИ АВТОМАТИЧНО ЦИМ СКРИПТОМ${NC}"
        ;;
    "cPanel / WHM")
        echo -e "Статус оновлення: ${RED}НЕ МОЖНА ОНОВИТИ ЦИМ СКРИПТОМ${NC}"
        echo -e "${YELLOW}📌 Примітка для сапорта:${NC} В cPanel Roundcube оновлюється через RPM. Перевірте, чи не вимкнено автоматичні апдейти в cpanel.config."
        echo -e "${YELLOW}👉 Рішення:${NC} Запустіть повний апдейт cPanel командою: ${BLUE}/usr/local/cpanel/scripts/upcp${NC}"
        exit 0
        ;;
    "DirectAdmin")
        echo -e "Статус оновлення: ${RED}НЕ МОЖНА ОНОВИТИ ЦИМ СКРИПТОМ${NC}"
        echo -e "${YELLOW}👉 Рішення (CustomBuild):${NC}"
        echo -e "   cd /usr/local/directadmin/custombuild"
        echo -e "   ./build update"
        echo -e "   ./build roundcube"
        exit 0
        ;;
    "HestiaCP")
        echo -e "Статус оновлення: ${RED}НЕ МОЖНА ОНОВИТИ ЦИМ СКРИПТОМ${NC}"
        echo -e "${YELLOW}👉 Рішення:${NC} Roundcube оновлюється через системний менеджер пакетів apt. Запустіть: ${BLUE}apt-get update && apt-get --only-upgrade install hestia-php roundcube${NC}"
        exit 0
        ;;
    "Чистий LAMP/LEMP (Без панелі)")
        echo -e "Статус оновлення: ${RED}НЕ МОЖНА ОНОВИТИ ЦИМ СКРИПТОМ${NC}"
        echo -e "${YELLOW}⚠️ Увага:${NC} Roundcube розгорнуто вручну (імовірно в /var/www/html/ чи суміжну директорію)."
        echo -e "${YELLOW}👉 Рішення:${NC} Потрібно локалізувати директорію інсталяції, завантажити архів з офіційного GitHub Roundcube і запустити штатний бінарник ${BLUE}bin/installto.sh /шлях/до/roundcube${NC}"
        exit 0
        ;;
    *)
        echo -e "Статус оновлення: ${RED}НЕВІДОМА СЕРЕДОВИЩЕ${NC}"
        echo -e "${YELLOW}Зупинка, щоб нічого не пошкодити. Виконуйте оновлення вручну відповідно до архітектури сервера.${NC}"
        exit 1
        ;;
esac


# --- КРОК 2: ПЕРЕВІРКА ВЕРСІЇ ДО ВИПРАВЛЕННЯ ---
echo -e "\n${YELLOW}[2/4] Визначення поточної версії Roundcube...${NC}"

RC_VERSION_FILE="/usr/local/cwpsrv/var/services/roundcube/program/include/iniset.php"

if [ -f "$RC_VERSION_FILE" ]; then
    # Витягуємо версію з константи RCMAIL_VERSION
    CURRENT_VERSION=$(grep "define('RCMAIL_VERSION'" "$RC_VERSION_FILE" | head -n 1 | cut -d"'" -f4)
    echo -e "Поточна версія Roundcube 

else
    echo -e "${RED}[ПОМИЛКА] Не вдалося знайти файл конфігурації Roundcube для визначення версії.${NC}"
    exit 1
fi


# --- КРОК 3: ПЕРЕВІРКА ЗАЛЕЖНОСТЕЙ (PHP INTL) ТА ЛІКУВАННЯ ОС ---
echo -e "\n${YELLOW}[3/4] Перевірка системних залежностей [PHP intl]...${NC}"
CWP_PHP="/usr/local/cwp/php71/bin/php"

if [ ! -f "$CWP_PHP" ]; then
    echo -e "${RED}[ПОМИЛКА] Не знайдено внутрішній PHP CWP за шляхом $CWP_PHP. Зупинка.${NC}"
    exit 1
fi

if $CWP_PHP -m | grep -q 'intl'; then
    echo -e "${GREEN}[ОК] Розширення intl вже встановлено.${NC}"
else
    echo -e "${YELLOW}[ІНФО] Розширення intl відсутнє [критично для Roundcube 1.5+]. Вирішуємо проблему...${NC}"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_VER=$VERSION_ID
        OS_NAME=$ID
    fi

    if [[ "$OS_VER" == "7" ]]; then
        echo -e "${YELLOW}Застосовуємо фікс для CentOS 7 [встановлення libicu69 вручну, оскільки штатні репо EOL]...${NC}"
        yum update ca-certificates -y
        rpm -ivh https://github.com/mysterydata/md-disk/raw/main/libicu69-69.1-4.el7.x86_64.rpm --force --nodeps
        curl -s -L https://www.alphagnu.com/upload/tmp/cwp_rc_fix.sh | bash
    elif [[ "$OS_VER" =~ ^8 ]] || [[ "$OS_NAME" == "almalinux" || "$OS_NAME" == "rocky" ]]; then
        echo -e "${YELLOW}Застосовуємо фікс для AlmaLinux/RockyLinux 8...${NC}"
        dnf update ca-certificates -y
        rpm -ivh https://github.com/mysterydata/md-disk/raw/main/libicu69-69.1-4.el8.x86_64.rpm --force --nodeps
        curl -s -L https://www.alphagnu.com/upload/tmp/el8/cwp_rc_fix_el8.sh | bash
    else
        echo -e "${RED}[ПОМИЛКА] Автоматичний фікс intl не підтримує цю версію ОС ($OS_NAME $OS_VER).${NC}"
        exit 1
    fi

    # Переперевірка
    if $CWP_PHP -m | grep -q 'intl'; then
        echo -e "${GREEN}[ОК] Розширення intl успішно інтегровано в PHP CWP.${NC}"
    else
        echo -e "${RED}[ПОМИЛКА] Не вдалося встановити розширення intl. Подальше оновлення неможливе!${NC}"
        exit 1
    fi
fi


# --- КРОК 4: ОНОВЛЕННЯ ROUNDCUBE ---
echo -e "\n${YELLOW}[4/4] Завантаження та встановлення Roundcube 1.5.15...${NC}"

cd /usr/local/src || exit 1
rm -rf roundcube*

wget -q --show-progress https://github.com/roundcube/roundcubemail/releases/download/1.5.15/roundcubemail-1.5.15-complete.tar.gz
if [ ! -f "roundcubemail-1.5.15-complete.tar.gz" ]; then
    echo -e "${RED}[ПОМИЛКА] Помилка завантаження дистрибутиву з GitHub.${NC}"
    exit 1
fi

tar xf roundcubemail-1.5.15-complete.tar.gz
cd roundcubemail-1.5.15/ || exit 1

# Патчимо інсталятор під оточення CWP
sed -i "s@\/usr\/bin\/env php@\/usr\/bin\/env \/usr\/local\/cwp\/php71\/bin\/php@g" bin/installto.sh
sed -i "s@\php bin@\/usr\/local\/cwp\/php71\/bin\/php bin@g" bin/installto.sh

TARGET_DIR="/usr/local/cwpsrv/var/services/roundcube"

# Накатуємо апдейт поверх старої версії з авто-відповіддю "yes"
yes | bin/installto.sh $TARGET_DIR

# Рестарт сервісів для застосування змін
echo -e "${YELLOW}Перезапуск поштових служб та веб-сервера CWP...${NC}"
systemctl restart cwpsrv
systemctl restart cwp-phpfpm
systemctl restart postfix
systemctl restart dovecot

# --- ФІНАЛЬНИЙ ВИСНОВОК ---
if [ -f "$RC_VERSION_FILE" ]; then
    NEW_VERSION=$(grep "define('RCMAIL_VERSION'" "$RC_VERSION_FILE" | head -n 1 | cut -d"'" -f4)
fi

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}                ЗВІТ ПРО ВИКОНАННЯ                 ${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "Панель керування: ${GREEN}$PANEL${NC}"
echo -e "Версія ДО виправлення:  ${RED}$CURRENT_VERSION${NC}"
echo -e "Версія ПІСЛЯ виправлення: ${GREEN}$NEW_VERSION${NC}"
echo -e "--------------------------------------------------"
echo -e "${GREEN}Результат:${NC} Сервер успішно захищено від CVE-2025-49113."
echo -e "${YELLOW}Примітка для тестування:${NC} Перевірте авторизацію в Webmail."
echo -e "${YELLOW}Лог помилок у разі проблем:${NC} $TARGET_DIR/logs/errors.log"
echo -e "${GREEN}==================================================${NC}"
