// Anki image-occlusion reviewer: Ankitects Pty Ltd and contributors. AGPL-3.0-or-later.
// Source: Vendor/anki at 96af4ca9d214e71743b1186fd2ceab1a7e7e3f32; adapter: tools/reviewer/build.mjs.
(() => {
  // mobile-i18n:@generated/ftl
  var notetypeErrorNoImageToShow = () => "No image to show.";

  // mobile-i18n:@tslib/i18n
  var ModuleName = { NOTETYPES: 0 };
  var setupI18n = async () => {
  };

  // ../../Vendor/anki/ts/routes/image-occlusion/canvas-scale.ts
  function optimumPixelSizeForCanvas(imageSize, containerSize) {
    let { width, height } = imageSize;
    const pixelScale = window.devicePixelRatio;
    containerSize.width *= pixelScale;
    containerSize.height *= pixelScale;
    const containerScale = Math.min(containerSize.width / imageSize.width, containerSize.height / imageSize.height);
    width *= containerScale;
    height *= containerScale;
    const maximumPixels = 4096 * 4096;
    const requiredPixels = width * height;
    if (requiredPixels > maximumPixels) {
      const shrinkScale = Math.sqrt(maximumPixels) / Math.sqrt(requiredPixels);
      width *= shrinkScale;
      height *= shrinkScale;
    }
    return {
      width: Math.floor(width),
      height: Math.floor(height)
    };
  }

  // mobile-editor:editor-only
  var fabric = new Proxy({}, { get() {
    throw new Error("Desktop canvas conversion is unavailable in the iOS reviewer.");
  } });

  // node_modules/svelte/src/internal/shared/utils.js
  var index_of = Array.prototype.indexOf;
  var includes = Array.prototype.includes;
  var object_prototype = Object.prototype;
  var array_prototype = Array.prototype;
  var noop = () => {
  };

  // node_modules/svelte/src/internal/client/constants.js
  var DERIVED = 1 << 1;
  var EFFECT = 1 << 2;
  var RENDER_EFFECT = 1 << 3;
  var MANAGED_EFFECT = 1 << 24;
  var BLOCK_EFFECT = 1 << 4;
  var BRANCH_EFFECT = 1 << 5;
  var ROOT_EFFECT = 1 << 6;
  var BOUNDARY_EFFECT = 1 << 7;
  var CONNECTED = 1 << 9;
  var CLEAN = 1 << 10;
  var DIRTY = 1 << 11;
  var MAYBE_DIRTY = 1 << 12;
  var INERT = 1 << 13;
  var DESTROYED = 1 << 14;
  var REACTION_RAN = 1 << 15;
  var DESTROYING = 1 << 25;
  var EFFECT_TRANSPARENT = 1 << 16;
  var EAGER_EFFECT = 1 << 17;
  var HEAD_EFFECT = 1 << 18;
  var EFFECT_PRESERVED = 1 << 19;
  var USER_EFFECT = 1 << 20;
  var EFFECT_OFFSCREEN = 1 << 25;
  var WAS_MARKED = 1 << 16;
  var REACTION_IS_UPDATING = 1 << 21;
  var ASYNC = 1 << 22;
  var ERROR_VALUE = 1 << 23;
  var STALE_REACTION = new class StaleReactionError extends Error {
    name = "StaleReactionError";
    message = "The reaction that called `getAbortSignal()` was re-run or destroyed";
  }();
  var IS_XHTML = (
    // We gotta write it like this because after downleveling the pure comment may end up in the wrong location
    !!globalThis.document?.contentType && /* @__PURE__ */ globalThis.document.contentType.includes("xml")
  );

  // node_modules/svelte/src/internal/client/reactivity/equality.js
  function safe_not_equal(a, b) {
    return a != a ? b == b : a !== b || a !== null && typeof a === "object" || typeof a === "function";
  }

  // node_modules/svelte/src/constants.js
  var EACH_INDEX_REACTIVE = 1 << 1;
  var EACH_IS_CONTROLLED = 1 << 2;
  var EACH_IS_ANIMATED = 1 << 3;
  var EACH_ITEM_IMMUTABLE = 1 << 4;
  var PROPS_IS_RUNES = 1 << 1;
  var PROPS_IS_UPDATED = 1 << 2;
  var PROPS_IS_BINDABLE = 1 << 3;
  var PROPS_IS_LAZY_INITIAL = 1 << 4;
  var TRANSITION_OUT = 1 << 1;
  var TRANSITION_GLOBAL = 1 << 2;
  var TEMPLATE_USE_IMPORT_NODE = 1 << 1;
  var TEMPLATE_USE_SVG = 1 << 2;
  var TEMPLATE_USE_MATHML = 1 << 3;
  var ELEMENT_PRESERVE_ATTRIBUTE_CASE = 1 << 1;
  var ELEMENT_IS_INPUT = 1 << 2;

  // node_modules/svelte/src/internal/client/reactivity/status.js
  var STATUS_MASK = ~(DIRTY | MAYBE_DIRTY | CLEAN);

  // node_modules/svelte/src/store/shared/index.js
  var subscriber_queue = [];
  function writable(value, start = noop) {
    let stop = null;
    const subscribers = /* @__PURE__ */ new Set();
    function set2(new_value) {
      if (safe_not_equal(value, new_value)) {
        value = new_value;
        if (stop) {
          const run_queue = !subscriber_queue.length;
          for (const subscriber of subscribers) {
            subscriber[1]();
            subscriber_queue.push(subscriber, value);
          }
          if (run_queue) {
            for (let i = 0; i < subscriber_queue.length; i += 2) {
              subscriber_queue[i][0](subscriber_queue[i + 1]);
            }
            subscriber_queue.length = 0;
          }
        }
      }
    }
    function update2(fn) {
      set2(fn(
        /** @type {T} */
        value
      ));
    }
    function subscribe(run, invalidate = noop) {
      const subscriber = [run, invalidate];
      subscribers.add(subscriber);
      if (subscribers.size === 1) {
        stop = start(set2, update2) || noop;
      }
      run(
        /** @type {T} */
        value
      );
      return () => {
        subscribers.delete(subscriber);
        if (subscribers.size === 0 && stop) {
          stop();
          stop = null;
        }
      };
    }
    return { set: set2, update: update2, subscribe };
  }

  // node_modules/svelte/src/internal/client/dom/blocks/boundary.js
  var flags = EFFECT_TRANSPARENT | EFFECT_PRESERVED;

  // ../../Vendor/anki/ts/routes/image-occlusion/store.ts
  var notesDataStore = writable({ id: "", title: "", divValue: "", textareaValue: "" }[0]);
  var tagsWritable = writable([""]);
  var ioMaskEditorVisible = writable(true);
  var hideAllGuessOne = writable(true);
  var ioImageLoadedStore = writable(false);
  var opacityStateStore = writable(false);
  var textEditingState = writable(false);
  var saveNeededStore = writable(false);

  // ../../Vendor/anki/ts/routes/image-occlusion/tools/lib.ts
  var SHAPE_MASK_COLOR = "#ffeba2";
  var TEXT_BACKGROUND_COLOR = "#ffffff";
  var TEXT_FONT_FAMILY = "Arial";
  var TEXT_PADDING = 5;
  var TEXT_FONT_SIZE = 40;
  var TEXT_COLOR = "#000000";

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/lib.ts
  function floatToDisplay(number) {
    if (Number.isNaN(number) || number == 0) {
      return ".0000";
    }
    return number.toFixed(4).replace(/^0+|0+$/g, "");
  }
  var ANGLE_STEPS = 1e4;
  function angleToStored(angle) {
    const angleDeg = Number(angle) % 360;
    return Number.isNaN(angleDeg) ? null : Math.round(angleDeg / 360 * ANGLE_STEPS);
  }
  function storedToAngle(x) {
    const angleSteps = Number(x) % ANGLE_STEPS;
    return Number.isNaN(angleSteps) ? null : angleSteps / ANGLE_STEPS * 360;
  }

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/position.ts
  function xToNormalized(size, x) {
    return x / size.width;
  }
  function yToNormalized(size, y) {
    return y / size.height;
  }
  function xFromNormalized(size, x) {
    return Math.round(x * size.width);
  }
  function yFromNormalized(size, y) {
    return Math.round(y * size.height);
  }

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/base.ts
  var Shape = class _Shape {
    constructor({ left = 0, top = 0, angle = 0, fill = SHAPE_MASK_COLOR, occludeInactive, ordinal = void 0 } = {}) {
      this.left = left;
      this.top = top;
      this.angle = angle;
      this.fill = fill;
      this.occludeInactive = occludeInactive;
      this.ordinal = ordinal;
    }
    /** Format numbers and remove default values, for easier serialization to
     * text.
     */
    toDataForCloze() {
      const angle = angleToStored(this.angle);
      return {
        left: floatToDisplay(this.left),
        top: floatToDisplay(this.top),
        ...!angle ? {} : { angle: angle.toString() }
      };
    }
    toFabric(size) {
      const absolute = this.toAbsolute(size);
      return new fabric.Object(absolute);
    }
    normalPosition(size) {
      return {
        left: xToNormalized(size, this.left),
        top: yToNormalized(size, this.top)
      };
    }
    toNormal(size) {
      return new _Shape({
        ...this,
        ...this.normalPosition(size)
      });
    }
    absolutePosition(size) {
      return {
        left: xFromNormalized(size, this.left),
        top: yFromNormalized(size, this.top)
      };
    }
    toAbsolute(size) {
      return new _Shape({
        ...this,
        ...this.absolutePosition(size)
      });
    }
  };

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/ellipse.ts
  var Ellipse = class _Ellipse extends Shape {
    constructor({ rx = 0, ry = 0, ...rest } = {}) {
      super(rest);
      this.rx = rx;
      this.ry = ry;
      this.id = "ellipse-" + (/* @__PURE__ */ new Date()).getTime();
    }
    toDataForCloze() {
      return {
        ...super.toDataForCloze(),
        rx: floatToDisplay(this.rx),
        ry: floatToDisplay(this.ry),
        ...this.fill === SHAPE_MASK_COLOR ? {} : { fill: this.fill }
      };
    }
    toFabric(size) {
      const absolute = this.toAbsolute(size);
      return new fabric.Ellipse(absolute);
    }
    toNormal(size) {
      return new _Ellipse({
        ...this,
        ...super.normalPosition(size),
        rx: xToNormalized(size, this.rx),
        ry: yToNormalized(size, this.ry)
      });
    }
    toAbsolute(size) {
      return new _Ellipse({
        ...this,
        ...super.absolutePosition(size),
        rx: xFromNormalized(size, this.rx),
        ry: yFromNormalized(size, this.ry)
      });
    }
  };

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/polygon.ts
  var Polygon = class _Polygon extends Shape {
    constructor({ points = [], ...rest } = {}) {
      super(rest);
      this.points = points;
      this.id = "polygon-" + (/* @__PURE__ */ new Date()).getTime();
    }
    toDataForCloze() {
      return {
        ...super.toDataForCloze(),
        points: this.points.map(({ x, y }) => `${floatToDisplay(x)},${floatToDisplay(y)}`).join(" "),
        ...this.fill === SHAPE_MASK_COLOR ? {} : { fill: this.fill }
      };
    }
    toFabric(size) {
      const absolute = this.toAbsolute(size);
      return new fabric.Polygon(absolute.points, absolute);
    }
    toNormal(size) {
      const points = [];
      this.points.forEach((p) => {
        points.push({
          x: xToNormalized(size, p.x),
          y: yToNormalized(size, p.y)
        });
      });
      return new _Polygon({
        ...this,
        ...super.normalPosition(size),
        points
      });
    }
    toAbsolute(size) {
      const points = [];
      this.points.forEach((p) => {
        points.push({
          x: xFromNormalized(size, p.x),
          y: yFromNormalized(size, p.y)
        });
      });
      return new _Polygon({
        ...this,
        ...super.absolutePosition(size),
        points
      });
    }
  };
  var Point = class {
    constructor({ x = 0, y = 0 } = {}) {
      this.x = 0;
      this.y = 0;
      this.x = x;
      this.y = y;
    }
  };

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/rectangle.ts
  var Rectangle = class _Rectangle extends Shape {
    constructor({ width = 0, height = 0, ...rest } = {}) {
      super(rest);
      this.width = width;
      this.height = height;
      this.id = "rect-" + (/* @__PURE__ */ new Date()).getTime();
    }
    toDataForCloze() {
      return {
        ...super.toDataForCloze(),
        width: floatToDisplay(this.width),
        height: floatToDisplay(this.height),
        ...this.fill === SHAPE_MASK_COLOR ? {} : { fill: this.fill }
      };
    }
    toFabric(size) {
      const absolute = this.toAbsolute(size);
      return new fabric.Rect(absolute);
    }
    toNormal(size) {
      return new _Rectangle({
        ...this,
        ...super.normalPosition(size),
        width: xToNormalized(size, this.width),
        height: yToNormalized(size, this.height)
      });
    }
    toAbsolute(size) {
      return new _Rectangle({
        ...this,
        ...super.absolutePosition(size),
        width: xFromNormalized(size, this.width),
        height: yFromNormalized(size, this.height)
      });
    }
  };

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/text.ts
  var Text2 = class _Text extends Shape {
    constructor({
      text = "",
      scaleX = 1,
      scaleY = 1,
      fill = TEXT_COLOR,
      fontSize,
      ...rest
    } = {}) {
      super(rest);
      this.fill = fill;
      this.text = text;
      this.scaleX = scaleX;
      this.scaleY = scaleY;
      this.fontSize = fontSize;
      this.id = "text-" + (/* @__PURE__ */ new Date()).getTime();
    }
    toDataForCloze() {
      return {
        ...super.toDataForCloze(),
        text: this.text,
        // scaleX and scaleY are guaranteed to be equal since we lock the aspect ratio
        scale: floatToDisplay(this.scaleX),
        fs: this.fontSize ? floatToDisplay(this.fontSize) : void 0,
        ...this.fill === TEXT_COLOR ? {} : { fill: this.fill }
      };
    }
    toFabric(size) {
      const absolute = this.toAbsolute(size);
      return new fabric.IText(absolute.text, {
        ...absolute,
        fontFamily: TEXT_FONT_FAMILY,
        backgroundColor: TEXT_BACKGROUND_COLOR,
        padding: TEXT_PADDING,
        lineHeight: 1,
        lockScalingFlip: true
      });
    }
    toNormal(size) {
      const fontSize = this.fontSize ? this.fontSize : TEXT_FONT_SIZE;
      return new _Text({
        ...this,
        fontSize: fontSize / size.height,
        ...super.normalPosition(size)
      });
    }
    toAbsolute(size) {
      return new _Text({
        ...this,
        fontSize: this.fontSize ? this.fontSize * size.height : TEXT_FONT_SIZE,
        ...super.absolutePosition(size)
      });
    }
  };

  // ../../Vendor/anki/ts/routes/image-occlusion/shapes/from-cloze.ts
  function extractShapesFromRenderedClozes(selector) {
    return Array.from(document.querySelectorAll(selector)).flatMap((cloze) => {
      if (cloze instanceof HTMLDivElement) {
        return extractShapeFromRenderedCloze(cloze) ?? [];
      } else {
        return [];
      }
    });
  }
  function extractShapeFromRenderedCloze(cloze) {
    const type = cloze.dataset.shape;
    if (type !== "rect" && type !== "ellipse" && type !== "polygon" && type !== "text") {
      return null;
    }
    const props = {
      occludeInactive: cloze.dataset.occludeinactive === "1",
      ordinal: parseInt(cloze.dataset.ordinal),
      left: cloze.dataset.left,
      top: cloze.dataset.top,
      width: cloze.dataset.width,
      height: cloze.dataset.height,
      rx: cloze.dataset.rx,
      ry: cloze.dataset.ry,
      points: cloze.dataset.points,
      text: cloze.dataset.text,
      scale: cloze.dataset.scale,
      fs: cloze.dataset.fontSize,
      angle: cloze.dataset.angle,
      ...cloze.dataset.fill == null ? {} : { fill: cloze.dataset.fill }
    };
    return buildShape(type, props);
  }
  function buildShape(type, props) {
    props.left = parseFloat(
      Number.isNaN(Number(props.left)) ? ".0000" : props.left
    );
    props.top = parseFloat(
      Number.isNaN(Number(props.top)) ? ".0000" : props.top
    );
    props.angle = storedToAngle(props.angle) ?? 0;
    switch (type) {
      case "rect": {
        return new Rectangle({
          ...props,
          width: parseFloat(props.width),
          height: parseFloat(props.height)
        });
      }
      case "ellipse": {
        return new Ellipse({
          ...props,
          rx: parseFloat(props.rx),
          ry: parseFloat(props.ry)
        });
      }
      case "polygon": {
        if (props.points !== "") {
          props.points = props.points.split(" ").map((point) => {
            const [x, y] = point.split(",");
            return new Point({ x, y });
          });
        } else {
          props.points = [new Point({ x: 0, y: 0 })];
        }
        return new Polygon(props);
      }
      case "text": {
        const textProps = {
          ...props,
          scaleX: parseFloat(props.scale),
          scaleY: parseFloat(props.scale)
        };
        if (props.fs) {
          textProps.fontSize = parseFloat(props.fs);
        }
        return new Text2(textProps);
      }
    }
  }

  // ../../Vendor/anki/ts/routes/image-occlusion/review.ts
  var imageOcclusionAPI = {
    setup: setupImageOcclusion,
    drawShape,
    Ellipse,
    Polygon,
    Rectangle,
    Shape,
    Text: Text2
  };
  async function setupImageOcclusion(setupOptions) {
    await waitForImage();
    window.addEventListener("load", () => {
      window.addEventListener("resize", () => setupImageOcclusion(setupOptions));
    });
    let drawn = false;
    const draw = () => {
      if (drawn) return;
      drawn = true;
      void setupImageOcclusionInner(setupOptions);
    };
    const fallback = window.setTimeout(draw, 250);
    window.requestAnimationFrame(() => {
      window.clearTimeout(fallback);
      draw();
    });
  }
  async function waitForImage() {
    const image = document.querySelector(
      "#image-occlusion-container img"
    );
    if (!image) {
      return;
    }
    if (image.complete) {
      return;
    }
    await new Promise((resolve) => {
      image.addEventListener("load", () => {
        resolve();
      });
      image.addEventListener("error", () => {
        resolve();
      });
    });
  }
  function calculateContainerSize(container, img) {
    const compStyle = getComputedStyle(container);
    const compMaxWidth = parseFloat(compStyle.getPropertyValue("max-width"));
    const vw = container.parentElement.clientWidth;
    const maxWidth = Number.isNaN(compMaxWidth) || compMaxWidth > vw ? vw : compMaxWidth;
    const defaultMaxHeight = document.documentElement.clientHeight * 0.95 - 40;
    const compMaxHeight = parseFloat(compStyle.getPropertyValue("max-height"));
    let maxHeight;
    if (Number.isNaN(compMaxHeight)) {
      maxHeight = Math.max(img.naturalHeight, defaultMaxHeight);
    } else if (compMaxHeight < defaultMaxHeight) {
      maxHeight = compMaxHeight;
    } else {
      maxHeight = Math.max(defaultMaxHeight, Math.min(img.naturalHeight, compMaxHeight));
    }
    const ratio = Math.min(
      maxWidth / img.naturalWidth,
      maxHeight / img.naturalHeight
    );
    return { width: img.naturalWidth * ratio, height: img.naturalHeight * ratio };
  }
  var oneTimeSetupDone = false;
  async function setupImageOcclusionInner(setupOptions) {
    const canvas = document.querySelector(
      "#image-occlusion-canvas"
    );
    if (canvas == null) {
      return;
    }
    const container = document.getElementById(
      "image-occlusion-container"
    );
    const image = document.querySelector(
      "#image-occlusion-container img"
    );
    if (image == null) {
      await setupI18n({
        modules: [
          ModuleName.NOTETYPES
        ]
      });
      container.innerText = notetypeErrorNoImageToShow();
      return;
    }
    if (CSS.supports("aspect-ratio: 1")) {
      container.style.aspectRatio = `${image.naturalWidth / image.naturalHeight}`;
    } else {
      const containerSize = calculateContainerSize(container, image);
      container.style.width = `${containerSize.width}px`;
      container.style.height = `${containerSize.height}px`;
    }
    const size = optimumPixelSizeForCanvas(
      { width: image.naturalWidth, height: image.naturalHeight },
      { width: canvas.clientWidth, height: canvas.clientHeight }
    );
    canvas.width = size.width;
    canvas.height = size.height;
    if (!oneTimeSetupDone) {
      window.addEventListener("keydown", (event) => {
        const button2 = document.getElementById("toggle");
        if (button2 && button2.style.display !== "none" && event.key === "M") {
          toggleMasks(setupOptions);
        }
      });
      oneTimeSetupDone = true;
    }
    const button = document.getElementById("toggle");
    if (button) {
      if (document.querySelector('[data-occludeinactive="1"]')) {
        button.addEventListener("click", () => toggleMasks(setupOptions));
      } else {
        button.style.display = "none";
      }
    }
    drawShapes(canvas, setupOptions?.onWillDrawShapes, setupOptions?.onDidDrawShapes);
  }
  function drawShapes(canvas, onWillDrawShapes, onDidDrawShapes, allowedShapes) {
    const context = canvas.getContext("2d");
    const size = canvas;
    const filterByAllowedShapes = (el) => allowedShapes && allowedShapes.length > 0 ? allowedShapes.some((s) => el instanceof s) : true;
    let activeShapes = extractShapesFromRenderedClozes(".cloze").filter(filterByAllowedShapes);
    let inactiveShapes = extractShapesFromRenderedClozes(".cloze-inactive").filter(filterByAllowedShapes);
    let highlightShapes = extractShapesFromRenderedClozes(".cloze-highlight").filter(filterByAllowedShapes);
    let properties = getShapeProperties();
    const processed = onWillDrawShapes?.({ activeShapes, inactiveShapes, highlightShapes, properties }, context);
    if (processed) {
      activeShapes = processed.activeShapes;
      inactiveShapes = processed.inactiveShapes;
      highlightShapes = processed.highlightShapes;
      properties = processed.properties;
    }
    for (const shape of activeShapes) {
      drawShape({
        context,
        size,
        shape,
        fill: properties.activeShapeColor,
        stroke: properties.activeBorder.color,
        strokeWidth: properties.activeBorder.width
      });
    }
    for (const shape of inactiveShapes.filter((s) => s.occludeInactive)) {
      drawShape({
        context,
        size,
        shape,
        fill: shape.fill !== SHAPE_MASK_COLOR ? shape.fill : properties.inActiveShapeColor,
        stroke: properties.inActiveBorder.color,
        strokeWidth: properties.inActiveBorder.width
      });
    }
    for (const shape of highlightShapes) {
      drawShape({
        context,
        size,
        shape,
        fill: properties.highlightShapeColor,
        stroke: properties.highlightShapeBorder.color,
        strokeWidth: properties.highlightShapeBorder.width
      });
    }
    onDidDrawShapes?.({
      activeShapes,
      inactiveShapes,
      highlightShapes,
      properties
    }, context);
  }
  function drawShape({
    context: ctx,
    size,
    shape,
    fill,
    stroke,
    strokeWidth
  }) {
    shape = shape.toAbsolute(size);
    ctx.fillStyle = fill;
    ctx.strokeStyle = stroke;
    ctx.lineWidth = strokeWidth;
    const angle = (shape.angle ?? 0) * Math.PI / 180;
    if (shape instanceof Rectangle) {
      if (angle) {
        ctx.save();
        ctx.translate(shape.left, shape.top);
        ctx.rotate(angle);
        ctx.translate(-shape.left, -shape.top);
      }
      ctx.fillRect(shape.left, shape.top, shape.width, shape.height);
      if (strokeWidth) {
        ctx.strokeRect(shape.left, shape.top, shape.width, shape.height);
      }
      if (angle) {
        ctx.restore();
      }
    } else if (shape instanceof Ellipse) {
      const adjustedLeft = shape.left + shape.rx;
      const adjustedTop = shape.top + shape.ry;
      if (angle) {
        ctx.save();
        ctx.translate(shape.left, shape.top);
        ctx.rotate(angle);
        ctx.translate(-shape.left, -shape.top);
      }
      ctx.beginPath();
      ctx.ellipse(
        adjustedLeft,
        adjustedTop,
        shape.rx,
        shape.ry,
        0,
        0,
        Math.PI * 2,
        false
      );
      ctx.closePath();
      ctx.fill();
      if (strokeWidth) {
        ctx.stroke();
      }
      if (angle) {
        ctx.restore();
      }
    } else if (shape instanceof Polygon) {
      const offset = getPolygonOffset(shape);
      ctx.save();
      ctx.translate(offset.x, offset.y);
      ctx.beginPath();
      ctx.moveTo(shape.points[0].x, shape.points[0].y);
      for (let i = 0; i < shape.points.length; i++) {
        ctx.lineTo(shape.points[i].x, shape.points[i].y);
      }
      ctx.closePath();
      ctx.fill();
      if (strokeWidth) {
        ctx.stroke();
      }
      ctx.restore();
    } else if (shape instanceof Text2) {
      ctx.save();
      ctx.font = `${shape.fontSize}px ${TEXT_FONT_FAMILY}`;
      ctx.textBaseline = "top";
      ctx.scale(shape.scaleX, shape.scaleY);
      const lines = shape.text.split("\n");
      const baseMetrics = ctx.measureText("M");
      const fontHeight = baseMetrics.actualBoundingBoxAscent + baseMetrics.actualBoundingBoxDescent;
      const lineHeight = 1.5 * fontHeight;
      const linePositions = [];
      let maxWidth = 0;
      let totalHeight = 0;
      for (let i = 0; i < lines.length; i++) {
        const textMetrics = ctx.measureText(lines[i]);
        linePositions.push({
          text: lines[i],
          x: shape.left / shape.scaleX,
          y: shape.top / shape.scaleY + i * lineHeight,
          width: textMetrics.width,
          height: lineHeight
        });
        if (textMetrics.width > maxWidth) {
          maxWidth = textMetrics.width;
        }
        totalHeight += lineHeight;
      }
      const left = shape.left / shape.scaleX;
      const top = shape.top / shape.scaleY;
      if (angle) {
        ctx.translate(left, top);
        ctx.rotate(angle);
        ctx.translate(-left, -top);
      }
      ctx.fillStyle = TEXT_BACKGROUND_COLOR;
      ctx.fillRect(
        left,
        top,
        maxWidth + TEXT_PADDING,
        totalHeight + TEXT_PADDING
      );
      ctx.fillStyle = shape.fill ?? "#000";
      for (const line of linePositions) {
        ctx.fillText(line.text, line.x, line.y);
      }
      ctx.restore();
    }
  }
  function getPolygonOffset(polygon) {
    const topLeft = topLeftOfPoints(polygon.points);
    return { x: polygon.left - topLeft.x, y: polygon.top - topLeft.y };
  }
  function topLeftOfPoints(points) {
    let top = points[0].y;
    let left = points[0].x;
    for (const point of points) {
      if (point.y < top) {
        top = point.y;
      }
      if (point.x < left) {
        left = point.x;
      }
    }
    return { x: left, y: top };
  }
  function getShapeProperties() {
    const canvas = document.getElementById("image-occlusion-canvas");
    const computedStyle = window.getComputedStyle(canvas);
    try {
      const activeShapeColor = computedStyle.getPropertyValue(
        "--active-shape-color"
      );
      const inActiveShapeColor = computedStyle.getPropertyValue(
        "--inactive-shape-color"
      );
      const highlightShapeColor = computedStyle.getPropertyValue(
        "--highlight-shape-color"
      );
      const inActiveShapeBorder = computedStyle.getPropertyValue(
        "--inactive-shape-border"
      );
      const inActiveBorder = inActiveShapeBorder.split(" ").filter((x) => x);
      const inActiveShapeBorderWidth = parseFloat(inActiveBorder[0]);
      const inActiveShapeBorderColor = inActiveBorder[1];
      const activeShapeBorder = computedStyle.getPropertyValue(
        "--active-shape-border"
      );
      const activeBorder = activeShapeBorder.split(" ").filter((x) => x);
      const activeShapeBorderWidth = parseFloat(activeBorder[0]);
      const activeShapeBorderColor = activeBorder[1];
      const highlightShapeBorder = computedStyle.getPropertyValue(
        "--highlight-shape-border"
      );
      const highlightBorder = highlightShapeBorder.split(" ").filter((x) => x);
      const highlightShapeBorderWidth = parseFloat(highlightBorder[0]);
      const highlightShapeBorderColor = highlightBorder[1];
      return {
        activeShapeColor: activeShapeColor ? activeShapeColor : "#ff8e8e",
        inActiveShapeColor: inActiveShapeColor ? inActiveShapeColor : SHAPE_MASK_COLOR,
        highlightShapeColor: highlightShapeColor ? highlightShapeColor : "#ff8e8e00",
        activeBorder: {
          width: !isNaN(activeShapeBorderWidth) ? activeShapeBorderWidth : 1,
          color: activeShapeBorderColor ? activeShapeBorderColor : "#212121"
        },
        inActiveBorder: {
          width: !isNaN(inActiveShapeBorderWidth) ? inActiveShapeBorderWidth : 1,
          color: inActiveShapeBorderColor ? inActiveShapeBorderColor : "#212121"
        },
        highlightShapeBorder: {
          width: !isNaN(highlightShapeBorderWidth) ? highlightShapeBorderWidth : 1,
          color: highlightShapeBorderColor ? highlightShapeBorderColor : "#ff8e8e"
        }
      };
    } catch {
      return {
        activeShapeColor: "#ff8e8e",
        inActiveShapeColor: "#ffeba2",
        highlightShapeColor: "#ff8e8e00",
        activeBorder: {
          width: 1,
          color: "#212121"
        },
        inActiveBorder: {
          width: 1,
          color: "#212121"
        },
        highlightShapeBorder: {
          width: 1,
          color: "#ff8e8e"
        }
      };
    }
  }
  var hide = false;
  var toggleMasks = (setupOptions) => {
    const canvas = document.getElementById("image-occlusion-canvas");
    const context = canvas.getContext("2d");
    hide = !hide;
    context.clearRect(0, 0, canvas.width, canvas.height);
    if (hide) {
      drawShapes(canvas, setupOptions?.onWillDrawShapes, setupOptions?.onDidDrawShapes, [Text2]);
      return;
    }
    drawShapes(canvas, setupOptions?.onWillDrawShapes, setupOptions?.onDidDrawShapes);
  };

  // ../../anki-ios-image-occlusion.ts
  window.anki = window.anki || {};
  window.anki.imageOcclusion = imageOcclusionAPI;
  window.anki.setupImageCloze = imageOcclusionAPI.setup;
  var style = document.createElement("style");
  style.textContent = "#image-occlusion-container {\n    position: relative;\n    margin: 0 auto;\n    max-height: calc(95vh - 40px);\n}\n\n#image-occlusion-container img {\n    position: absolute;\n    top: 0;\n    left: 0;\n    width: 100%;\n    height: 100%;\n    max-width: unset;\n    max-height: unset;\n}\n\n#image-occlusion-canvas {\n    position: absolute;\n    top: 0;\n    left: 0;\n    width: 100%;\n    height: 100%;\n}\n";
  document.head.append(style);
})();
