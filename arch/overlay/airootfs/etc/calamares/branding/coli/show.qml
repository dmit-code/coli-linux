import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    titleColor: "#FFFFFF"
    textColor: "#D7E5FF"
    fontFamily: "Noto Sans"

    Slide {
        centeredText: qsTr("Добро пожаловать в COLI Linux")
    }
    Slide {
        centeredText: qsTr("Настройте язык, клавиатуру и учётную запись")
    }
    Slide {
        centeredText: qsTr("Не выключайте компьютер до завершения установки")
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }
    function onLeave() {
    }
}
