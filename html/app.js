const postResult = async (payload) => {
    await fetch(`https://${GetParentResourceName()}/mugshotCropResult`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(payload),
    });
};

const postReady = async () => {
    await fetch(`https://${GetParentResourceName()}/mugshotCropperReady`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify({ ok: true }),
    });
};

const cropToTarget = (image, targetWidth, targetHeight) => {
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    const targetAspect = targetWidth / targetHeight;
    const sourceAspect = image.width / image.height;

    let sourceWidth = image.width;
    let sourceHeight = image.height;
    let sourceX = 0;
    let sourceY = 0;

    if (sourceAspect > targetAspect) {
        sourceWidth = image.height * targetAspect;
        sourceX = (image.width - sourceWidth) / 2;
    } else {
        sourceHeight = image.width / targetAspect;
        sourceY = (image.height - sourceHeight) / 2;
    }

    canvas.width = targetWidth;
    canvas.height = targetHeight;

    context.drawImage(
        image,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
        0,
        0,
        targetWidth,
        targetHeight,
    );

    return canvas.toDataURL('image/png');
};

window.addEventListener('message', async (event) => {
    const data = event.data;

    if (!data || data.type !== 'cropMugshot') {
        return;
    }

    try {
        const image = new Image();

        image.onload = async () => {
            try {
                const mugshot = cropToTarget(image, data.width || 200, data.height || 250);
                await postResult({ token: data.token, mugshot });
            } catch (_error) {
                await postResult({ token: data.token, mugshot: '' });
            }
        };

        image.onerror = async () => {
            await postResult({ token: data.token, mugshot: '' });
        };

        image.src = data.mugshot;
    } catch (_error) {
        await postResult({ token: data.token, mugshot: '' });
    }
});

window.addEventListener('load', () => {
    postReady().catch(() => {});
});