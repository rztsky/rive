// Инициализация Rive
const rive = new rive.Rive({
    src: 'assets/animation.riv', // Путь к вашему .riv файлу
    canvas: document.getElementById('canvas'),
    autoplay: false,
    stateMachines: 'State Machine 1', // Имя state machine из Rive Editor
    onLoad: () => {
        console.log('Анимация загружена!');
        rive.resizeDrawingSurfaceToCanvas();
    },
    onError: (err) => {
        console.error('Ошибка загрузки:', err);
    }
});

// Управление кнопками
document.getElementById('play').addEventListener('click', () => {
    rive.play();
});

document.getElementById('pause').addEventListener('click', () => {
    rive.pause();
});

document.getElementById('reset').addEventListener('click', () => {
    rive.reset();
});

// Адаптация под размер экрана
window.addEventListener('resize', () => {
    rive.resizeDrawingSurfaceToCanvas();
});
