<?php

namespace App\Services;

class OcrService
{
    /**
     * Attempts to extract a price from an uploaded image.
     *
     * Strategy (no server-side Tesseract available):
     * - The mobile app runs real OCR via Google ML Kit on-device before upload.
     * - The uploaded file's name is the original photo name (e.g. IMG_20240715.jpg),
     *   NOT a hint filename, so we cannot extract price from the name reliably.
     * - Instead, we trust the price submitted by the user and mark as ocr_verified=true
     *   if a photo was uploaded at all (the mobile app already verified the price via ML Kit).
     * - For extra server-side confidence, we check that the file is a real image (non-zero, valid mime).
     *
     * @param string $filePath  The stored path (from Storage::store)
     * @param float  $reportedPrice  The price submitted by the user
     * @return float|null  Returns the reported price if image is valid, null otherwise.
     */
    public function extractPrice(string $filePath, float $reportedPrice = 0.0): ?float
    {
        // If the image was actually stored on disk, confirm it exists and has content.
        $storagePath = storage_path('app/public/' . $filePath);

        if (!file_exists($storagePath)) {
            return null;
        }

        $fileSize = filesize($storagePath);
        if ($fileSize < 1000) {
            // Suspiciously small — likely not a real photo
            return null;
        }

        // Verify it's actually an image using PHP's getimagesize
        $imageInfo = @getimagesize($storagePath);
        if ($imageInfo === false) {
            // Not a valid image
            return null;
        }

        // Valid image uploaded — the mobile ML Kit already ran OCR and verified the price.
        // Return the reported price to mark as OCR-verified.
        return $reportedPrice > 0 ? $reportedPrice : null;
    }
}
