#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H

// Simple error handling macro
#define CHECK_ERROR(err, msg) \
    if (err) { \
        fprintf(stderr, "%s: %d\n", msg, err); \
        return EXIT_FAILURE; \
    }

// Function to save the RGBA buffer as a PPM file (for visualization)
void save_rgba_to_ppm(const char *filename, unsigned char *buffer, 
                      int width, int height) {
    FILE *fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "Failed to open file for writing: %s\n", filename);
        return;
    }
    
    // Write PPM header
    fprintf(fp, "P6\n%d %d\n255\n", width, height);
    
    // Write RGB data (ignore alpha)
    for (int i = 0; i < height; i++) {
        for (int j = 0; j < width; j++) {
            int idx = (i * width + j) * 4;
            // Blend with white background based on alpha
            unsigned char alpha = buffer[idx + 3];
            unsigned char r = (buffer[idx] * alpha + 255 * (255 - alpha)) / 255;
            unsigned char g = (buffer[idx + 1] * alpha + 255 * (255 - alpha)) / 255;
            unsigned char b = (buffer[idx + 2] * alpha + 255 * (255 - alpha)) / 255;
            
            fputc(r, fp);
            fputc(g, fp);
            fputc(b, fp);
        }
    }
    
    fclose(fp);
    printf("Saved output to %s\n", filename);
}

int main2() {
    // Default parameters
    const char *font_path = "C:\\Windows\\Fonts\\arial.ttf";
    char character = 'A';
    int size_px = 48;
    
    // Initialize FreeType
    FT_Library library;
    FT_Error error = FT_Init_FreeType(&library);
    CHECK_ERROR(error, "Failed to initialize FreeType");
    
    // Load font face
    FT_Face face;
    error = FT_New_Face(library, font_path, 0, &face);
    CHECK_ERROR(error, "Failed to load font");
    
    // Set font size
    error = FT_Set_Pixel_Sizes(face, 0, size_px);
    CHECK_ERROR(error, "Failed to set font size");
    
    // Get glyph index
    FT_UInt glyph_index = FT_Get_Char_Index(face, character);
    if (glyph_index == 0) {
        fprintf(stderr, "Character not found in font\n");
        FT_Done_Face(face);
        FT_Done_FreeType(library);
        return EXIT_FAILURE;
    }
    
    // Load and render the glyph
    error = FT_Load_Glyph(face, glyph_index, FT_LOAD_DEFAULT);
    CHECK_ERROR(error, "Failed to load glyph");
    
    // Render the glyph to a bitmap with anti-aliasing
    error = FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL);
    CHECK_ERROR(error, "Failed to render glyph");
    
    // Get bitmap dimensions
    FT_Bitmap bitmap = face->glyph->bitmap;
    int bitmap_width = bitmap.width;
    int bitmap_height = bitmap.rows;
    
    // Create our output buffer with some padding
    int buffer_width = bitmap_width + 10;
    int buffer_height = bitmap_height + 10;
    unsigned char *rgba_buffer = (unsigned char *)calloc(buffer_width * buffer_height * 4, sizeof(unsigned char));
    if (!rgba_buffer) {
        fprintf(stderr, "Failed to allocate memory for buffer\n");
        FT_Done_Face(face);
        FT_Done_FreeType(library);
        return EXIT_FAILURE;
    }
    
    // Calculate position with some padding
    int start_x = 5;
    int start_y = 5;
    
    // Copy bitmap data to RGBA buffer
    for (int y = 0; y < bitmap_height; y++) {
        for (int x = 0; x < bitmap_width; x++) {
            // Get alpha value from bitmap
            unsigned char alpha = bitmap.buffer[y * bitmap.pitch + x];
            
            // Calculate position in RGBA buffer
            int rgba_pos = ((start_y + y) * buffer_width + (start_x + x)) * 4;
            
            // Set RGBA values (black text with alpha)
            rgba_buffer[rgba_pos] = 0;           // R
            rgba_buffer[rgba_pos + 1] = 0;       // G
            rgba_buffer[rgba_pos + 2] = 0;       // B
            rgba_buffer[rgba_pos + 3] = alpha;   // A
        }
    }
    
    // Save as a PPM file for visualization
    char output_filename[128];
    sprintf(output_filename, "glyph_%c_%dpx.ppm", character, size_px);
    save_rgba_to_ppm(output_filename, rgba_buffer, buffer_width, buffer_height);
    
    // Print glyph metrics
    printf("Glyph metrics for '%c':\n", character);
    printf("  Width: %d pixels\n", bitmap_width);
    printf("  Height: %d pixels\n", bitmap_height);
    printf("  Advance width: %.2f pixels\n", face->glyph->advance.x / 64.0);
    printf("  Bearing X: %d pixels\n", face->glyph->bitmap_left);
    printf("  Bearing Y: %d pixels\n", face->glyph->bitmap_top);
    
    // Cleanup
    free(rgba_buffer);
    FT_Done_Face(face);
    FT_Done_FreeType(library);
    
    return EXIT_SUCCESS;
}
